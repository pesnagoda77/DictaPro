import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';
import 'package:hive/hive.dart';
import 'audio_service.dart' hide DialogueSegment;
import 'subscription_page.dart';
import 'theme/app_theme.dart';
import 'models/transcription.dart';

import 'services/stt_provider.dart';
import 'services/gigaam_service.dart';
import 'services/audio_convert.dart';
import 'services/glossary_service.dart';
import 'services/online_transcribe_service.dart';
import 'services/keep_alive.dart';
import 'services/purchase_service.dart';
import 'services/usage_limit_service.dart';
import 'services/local_notify.dart';
import 'dialogue_editor.dart';
import 'tag_service.dart';
import 'app_strings.dart';
import 'widgets/dicta_ui.dart';
import 'export_service.dart';
import 'player_page.dart';
import 'settings_page.dart';
import 'summary_page.dart';
import 'summary_service.dart';
import 'services/enhanced_summary_service.dart';
import 'widgets/operation_progress.dart';
import 'models/recording_details_model.dart';


enum SortOption {
  dateNewest,
  dateOldest,
  nameAsc,
  durationLongest,
  durationShortest,
}

extension SortOptionExtension on SortOption {
  String get label {
    switch (this) {
      case SortOption.dateNewest:
        return 'sort_date_newest';
      case SortOption.dateOldest:
        return 'sort_date_oldest';
      case SortOption.nameAsc:
        return 'sort_name_asc';
      case SortOption.durationLongest:
        return 'sort_duration_longest';
      case SortOption.durationShortest:
        return 'sort_duration_shortest';
    }
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.tab = 0});

  /// 0 — записи, 1 — тексты (только расшифрованное), 2 — итоги.
  final int tab;

  @override
  State createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _isRecording = false;
  double _level = 0;
  StreamSubscription<double>? _levelSub;
  List<Recording> _recordings = [];
  SortOption _sortOption = SortOption.dateNewest;
  int _recordSeconds = 0;
  double _amplitude = 0.0;
  String _searchQuery = '';
  bool _isSearching = false;
  bool _showFavoritesOnly = false;
  /// 0 — все, 1 — сегодня, 2 — в очереди (без расшифровки).
  int _quickFilter = 0;
  Timer? _timer;
  late AnimationController _pulseController;
  final _searchController = TextEditingController();
  final _hotwordsController = TextEditingController();
  List<String> _recentHotwords = [];
  // Одна строка состояния распознавания (task 019, дизайн V3):
  // движок один — GigaAM v3, модель вложена в сборку.
  String get _engineLabel => AppStrings.t('engine_label', context);

  /// Task 056: расшифровка завершилась, пока приложение было в фоне —
  /// при возврате показываем плашку «готово» (уведомление уже ушло в шторку).
  bool _finishedInBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Задача 036: подчищаем остатки прошлых прогонов (старые временные файлы).
    TranscribeKeepAlive.sweepOldTemp();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _loadRecordings();
    _loadSortPreference();
    _loadRecentHotwords();
    // Задача 038: баннер о незаконченной расшифровке показываем сразу
    // при открытии приложения, а не только при повторном запуске того
    // же файла.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUnfinishedTranscription();
    });
    _liveTimer = Timer.periodic(const Duration(seconds: 3), (_) => _refreshLiveStatus());
  }

  /// Обновляет состояние живой плашки: идёт ли расшифровка и сколько готово.
  Future<void> _refreshLiveStatus() async {
    try {
      final saved = await TranscribeKeepAlive.readPartial();
      final running = await TranscribeKeepAlive.isRunning();
      final marker = await TranscribeKeepAlive.readActiveMarker();
      final text = (saved?.$2 ?? '').trim();
      // Активной считаем задачу, если служба жива и есть либо маркер старта,
      // либо уже сохранённый кусок текста.
      final active = running && (marker != null || text.isNotEmpty);
      if (!mounted) return;
      // Task 045: partial стёрт (расшифровка завершена/убрана) — убираем
      // и карточку восстановления.
      if (saved == null && _recoveryJob != null) {
        setState(() => _recoveryJob = null);
      }
      final chunks = saved?.$1 ?? 0;
      final path = saved?.$3;
      final startedMs = marker?.$1 ?? 0;
      final stage = marker?.$2 ?? '';
      if (active != _liveActive ||
          chunks != _liveChunks ||
          text.length != _liveChars ||
          path != _livePath ||
          startedMs != _liveStartedMs ||
          stage != _liveStage) {
        final wasActive = _liveActive;
        setState(() {
          _liveActive = active;
          _liveChunks = chunks;
          _liveChars = text.length;
          _livePath = path;
          _liveStartedMs = startedMs;
          _liveStage = stage;
        });
        // Расшифровка завершилась — перечитываем список, чтобы текст появился на экране
        if (wasActive && !active) _loadRecordings();
      }
    } catch (_) {}
  }

  /// Живая плашка «Идёт расшифровка» — видно, что процесс пошёл и сколько готово.
  Widget _liveStatusCard() {
    String shortName = '';
    final p = _livePath;
    if (p != null && p.isNotEmpty) {
      shortName = p.split(RegExp(r'[\\/]')).last;
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const SizedBox(
              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppStrings.t('transcribing_now', context),
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  [
                    if (_liveStartedMs > 0)
                      AppStrings.tf('live_running_min', context, {'m': '${((DateTime.now().millisecondsSinceEpoch - _liveStartedMs) / 60000).floor()}'}),
                    AppStrings.tf('live_chunks_done', context, {'n': '$_liveChunks'}),
                    AppStrings.tf('live_chars', context, {'n': '$_liveChars'}),
                    if (shortName.isNotEmpty) shortName,
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_liveStage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(_liveStage,
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Task 045: при открытии приложения ищем оборванную расшифровку и
  /// показываем карточку восстановления (видна всегда, не исчезает,
  /// пока пользователь не выбрал действие). Раньше был MaterialBanner —
  /// его легко пропустить, и текст терялся.
  Future<void> _checkUnfinishedTranscription() async {
    final saved = await TranscribeKeepAlive.readPartial();
    if (!mounted) return;
    if (saved == null || saved.$2.trim().isEmpty) {
      setState(() => _recoveryJob = null);
      return;
    }
    setState(() => _recoveryJob = saved);
  }

  /// Кнопка [Продолжить] карточки: находим запись по пути из partial.txt
  /// и идём полным путём расшифровки — с автоматическим продолжением
  /// с куска M, без лишнего диалога (task 045).
  Future<void> _resumeRecoveryJob() async {
    final job = _recoveryJob;
    if (job == null) return;
    setState(() => _recoveryJob = null);
    final path = job.$3;
    if (path != null) {
      try {
        Recording? rec;
        for (final r in _recordings) {
          if (r.filePath == path) {
            rec = r;
            break;
          }
        }
        if (rec != null) {
          await _transcribeRecording(rec, resumeFromPartial: true);
          return;
        }
      } catch (_) {}
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            AppStrings.t('recovery_resume_hint', context)),
      ));
    }
  }

  /// Кнопка [Показать текст]: сохраняем накопленный текст отдельной
  /// записью и открываем его — результат не теряется (task 045).
  Future<void> _showRecoveryText() async {
    final job = _recoveryJob;
    if (job == null) return;
    try {
      final now = DateTime.now();
      final rec = Recording(
        id: now.millisecondsSinceEpoch.toString(),
        filePath: '',
        createdAt: now,
        durationMs: 0,
        fileSize: 0,
        title: AppStrings.t('recovery_saved_title', context),
        transcription: job.$2.trim(),
      );
      await AudioService().updateRecording(rec);
      await TranscribeKeepAlive.clearPartial();
      setState(() => _recoveryJob = null);
      _loadRecordings();
      _openDialogueEditor(rec);
    } catch (_) {}
  }

  Future<void> _discardRecoveryJob() async {
    await TranscribeKeepAlive.clearPartial();
    if (mounted) setState(() => _recoveryJob = null);
  }

  /// Карточка восстановления: «Расшифровка прервана · N символов · кусок M»
  /// с действиями [Продолжить] и [Показать текст] (task 045).
  Widget _recoveryCard() {
    final job = _recoveryJob;
    if (job == null) return const SizedBox.shrink();
    final chunks = job.$1;
    final chars = job.$2.trim().length;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppStrings.t('recovery_interrupted', context),
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: scheme.onErrorContainer)),
                    const SizedBox(height: 2),
                    Text(
                      [
                        AppStrings.tf('recovery_chars', context, {'n': '$chars'}),
                        if (chunks > 0) AppStrings.tf('recovery_chunk', context, {'n': '$chunks'}),
                      ].join(' · '),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onErrorContainer),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton(
                onPressed: _showRecoveryText,
                child: Text(AppStrings.t('recovery_show_text', context)),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _resumeRecoveryJob,
                child: Text(AppStrings.t('long_transcribe_continue', context)),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: AppStrings.t('btn_delete', context),
                onPressed: _discardRecoveryJob,
                icon: Icon(Icons.close, size: 18, color: scheme.onErrorContainer),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _loadRecentHotwords() async {
    final words = await HotwordsStorage.recent();
    if (mounted && words.isNotEmpty) {
      setState(() => _recentHotwords = words);
    }
  }

  Future<void> _loadSortPreference() async {
    try {
      final box = await Hive.openBox<dynamic>('settings');
      final raw = box.get('sortOption');
      if (raw != null) {
        final option = SortOption.values.firstWhere(
          (e) => e.name == raw,
          orElse: () => SortOption.dateNewest,
        );
        if (mounted) {
          setState(() => _sortOption = option);
        }
      }
    } catch (_) {
      // ignore
    }
  }

  Future<void> _saveSortPreference(SortOption option) async {
    try {
      final box = await Hive.openBox<dynamic>('settings');
      await box.put('sortOption', option.name);
    } catch (_) {
      // ignore
    }
  }

  void _loadRecordings() {
    // Task 034: батч может закончиться после ухода с экрана — setState
    // по уничтоженному State уронил бы приложение.
    if (!mounted) return;
    setState(() => _recordings = AudioService().getAllRecordings());
  }

  List<Recording> get _filteredRecordings {
    var list = List<Recording>.from(_recordings);
    if (_showFavoritesOnly) {
      list = list.where((rec) => rec.isFavorite).toList();
    }
    // Задача 068: чипы «Все / Сегодня / В очереди».
    if (_quickFilter == 1) {
      final now = DateTime.now();
      list = list
          .where((rec) =>
              rec.createdAt.year == now.year &&
              rec.createdAt.month == now.month &&
              rec.createdAt.day == now.day)
          .toList();
    } else if (_quickFilter == 2) {
      list = list
          .where((rec) => (rec.transcription ?? '').trim().isEmpty)
          .toList();
    }
    // Задача 068: вкладки «Тексты» и «Итоги» — те же записи, но с фильтром.
    if (widget.tab == 1) {
      list = list
          .where((rec) => (rec.transcription ?? '').trim().isNotEmpty)
          .toList();
    } else if (widget.tab == 2) {
      list = list
          .where((rec) => (rec.summary ?? '').trim().isNotEmpty)
          .toList();
    }
    if (_searchQuery.isNotEmpty) {
      list = list.where((rec) {
        final text = rec.transcription?.toLowerCase() ?? '';
        final title = (rec.title ?? '').toLowerCase();
        final name = AppStrings.tf('recording_of', context,
            {'d': DateFormat('dd.MM HH:mm').format(rec.createdAt)})
            .toLowerCase();
        return text.contains(_searchQuery.toLowerCase()) ||
            title.contains(_searchQuery.toLowerCase()) ||
            name.contains(_searchQuery.toLowerCase());
      }).toList();
    }
    switch (_sortOption) {
      case SortOption.dateNewest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case SortOption.dateOldest:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case SortOption.nameAsc:
        list.sort((a, b) {
          final aName = (a.title ?? '').toLowerCase();
          final bName = (b.title ?? '').toLowerCase();
          return aName.compareTo(bName);
        });
        break;
      case SortOption.durationLongest:
        list.sort((a, b) => b.durationMs.compareTo(a.durationMs));
        break;
      case SortOption.durationShortest:
        list.sort((a, b) => a.durationMs.compareTo(b.durationMs));
        break;
    }
    return list;
  }

  void _startTimer() {
    _recordSeconds = 0;
    _amplitude = 0.0;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() {
        _recordSeconds++;
        // затухание индикатора: полоса не «висит» на прошлом значении
        _level *= 0.85;
      });
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _recordSeconds = 0;
    _amplitude = 0.0;
  }

  String _fmtTime(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  /// Состояние «пусто»: говорим, что делать дальше, а не просто «нет записей».
  Widget _emptyState() {
    final isSearch = _searchQuery.isNotEmpty;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSearch
                  ? Icons.search_off
                  : widget.tab == 1
                      ? Icons.article_outlined
                      : widget.tab == 2
                          ? Icons.auto_awesome_outlined
                          : Icons.mic_none,
              size: 56,
              color: scheme.onSurface.withOpacity(0.25),
            ),
            const SizedBox(height: 14),
            Text(
              isSearch
                  ? AppStrings.t('empty_search_title', context)
                  : widget.tab == 1
                      ? AppStrings.t('empty_no_transcripts_title', context)
                      : widget.tab == 2
                          ? AppStrings.t('empty_no_summaries_title', context)
                          : AppStrings.t('empty_rec_title', context),
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isSearch
                  ? AppStrings.t('empty_search_body', context)
                  : widget.tab == 1
                      ? AppStrings.t('empty_no_transcripts_body', context)
                      : widget.tab == 2
                          ? AppStrings.t('empty_no_summaries_body', context)
                          : AppStrings.t('empty_rec_body', context),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _fmtDuration(int ms) {
    final s = (ms ~/ 1000);
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  Future<void> _showSleepTimerDialog() async {
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.t('timer_dialog_title', context)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.timer_off),
              title: Text(AppStrings.t('timer_none', context)),
              onTap: () => Navigator.pop(ctx, 0),
            ),
            ListTile(
              leading: const Icon(Icons.timer),
              title: Text(AppStrings.t('minutes_15', context)),
              onTap: () => Navigator.pop(ctx, 15),
            ),
            ListTile(
              leading: const Icon(Icons.timer),
              title: Text(AppStrings.t('minutes_30', context)),
              onTap: () => Navigator.pop(ctx, 30),
            ),
            ListTile(
              leading: const Icon(Icons.timer),
              title: Text(AppStrings.t('minutes_60', context)),
              onTap: () => Navigator.pop(ctx, 60),
            ),
          ],
        ),
      ),
    );

    if (selected == null) return;
    if (selected == 0) {
      AudioService().cancelSleepTimer();
      setState(() {});
      return;
    }

    AudioService().setSleepTimer(selected, () {
      if (mounted) {
        setState(() => _isRecording = false);
        _stopTimer();
        _loadRecordings();
      }
    });
    setState(() {});
  }

  bool _isTranscribing = false;

  // Task 034: этап операции для диалога прогресса (расшифровка → саммари).
  final ValueNotifier<String> _opStage = ValueNotifier('');

  // Живая плашка: показываем, что расшифровка идёт (даже если интерфейс
  // перезапускался и окно прогресса потерялось).
  bool _liveActive = false;
  int _liveChunks = 0;
  int _liveChars = 0;
  String? _livePath;
  int _liveStartedMs = 0;
  String _liveStage = '';
  Timer? _liveTimer;

  // Task 045: карточка «Расшифровка прервана» — состояние задачи с диска
  // (partial.txt): куски, текст, файл, статус, время старта. Видна сразу
  // при открытии приложения, а не прячется в баннере.
  (int, String, String?, String, int)? _recoveryJob;


  void _showTranscribingDialog() {
    // Task 041: повторный вход (двойной тап, батч + ручной запуск)
    // не должен запускать вторую конвертацию и второй диалог.
    if (_isTranscribing) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.t('transcribe_already', context))),
      );
      return;
    }
    _isTranscribing = true;
    _opStage.value = AppStrings.t('op_transcribing', context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        // Task 034: спиннер с тикающим счётчиком секунд и этапом —
        // операция перестала выглядеть зависшей.
        content: OperationProgressView(stage: _opStage),
      ),
    );
  }

  void _hideTranscribingDialog() {
    if (_isTranscribing && mounted) {
      _isTranscribing = false;
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  bool _isExporting = false;

  void _showExportingDialog() {
    _isExporting = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Text(AppStrings.t('creating_pdf', ctx)),
          ],
        ),
      ),
    );
  }

  void _hideExportingDialog() {
    if (_isExporting && mounted) {
      _isExporting = false;
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  /// Онлайн-транскрипт (если включён и есть ключ). null -> использовать офлайн.
  Future<String?> _onlineTranscript(String path) async {
    try {
      if (!await SttSettings.isEnabled()) return null;
      final provider = SttProvider.byId(await SttSettings.providerId());
      final key = await SttSettings.apiKey(provider.keyPrefsName);
      if (key == null) return null;
      if (!await SttSettings.hasConsent()) {
        if (!mounted) return null;
        final ok = await _showOfflineWarning(provider.title);
        if (ok != true) return null;
        await SttSettings.setConsent();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppStrings.t('online_recognizing', context)), duration: Duration(seconds: 2)));
      }
      return await OnlineTranscribeService.transcribe(path,
          provider: provider, apiKey: key);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppStrings.tf('online_failed', context, {'e': '$e'})),
            duration: const Duration(seconds: 4)));
      }
      return null;
    }
  }

  /// Мягкое предупреждение о выходе из офлайн-режима.
  Future<bool?> _showOfflineWarning(String providerTitle) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.t('offline_warn_title', context)),
        content: Text(
            AppStrings.tf('offline_warn_body', ctx, {'p': providerTitle}),
            style: const TextStyle(fontSize: 14, height: 1.4)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppStrings.t('stay_offline', ctx))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(AppStrings.t('recognize_online', ctx))),
        ],
      ),
    );
  }

  /// Офлайн-транскрибация (task 019): движок один — GigaAM v3, модель
  /// вложена в сборку. Не-WAV и не 16 кГц конвертируем нативным каналом,
  /// дальше стандартный путь (VAD + изолят) без изменений.
  /// При первом запуске показываем прогресс локального копирования модели
  /// («Подготовка модели: X%») — без сети, без возможности отменить.
  /// Выбор языка расшифровки при «В текст». Спрашиваем, если пользователь
  /// не отметил «больше не спрашивать»; иначе используем сохранённый выбор.
  Future<String?> _chooseAsrLang() async {
    var saved = AppStrings.defaultAsrLang();
    var ask = true;
    try {
      final sbox = await Hive.openBox<dynamic>('settings');
      final v = sbox.get('asr_lang')?.toString();
      if (v != null && v.isNotEmpty) saved = v;
      // Разовая миграция: раньше «Больше не спрашивать» стояло включённым
      // по умолчанию и первый же выбор отключал диалог навсегда. Возвращаем.
      if (sbox.get('asr_ask_reset_v2') != true) {
        await sbox.put('asr_ask', true);
        await sbox.put('asr_ask_reset_v2', true);
      }
      ask = (sbox.get('asr_ask') ?? true) == true;
    } catch (_) {}
    if (!ask) return saved;

    var dontAsk = false;
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(AppStrings.t('asr_dialog_title', ctx)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final e in const [
                ('ru', 'Русский'),
                ('en', 'English'),
                ('de', 'Deutsch'),
                ('fr', 'Français'),
                ('es', 'Español'),
                ('it', 'Italiano'),
              ])
                RadioListTile<String>(
                  value: e.$1,
                  groupValue: saved,
                  dense: true,
                  title: Text(e.$2),
                  onChanged: (v) => Navigator.pop(ctx, v),
                ),
              CheckboxListTile(
                value: dontAsk,
                dense: true,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setSt(() => dontAsk = v ?? false),
                title: Text(AppStrings.t('asr_dont_ask', ctx),
                    style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
    if (res == null) return null;
    try {
      final sbox = await Hive.openBox<dynamic>('settings');
      await sbox.put('asr_lang', res);
      await sbox.put('asr_ask', !dontAsk);
    } catch (_) {}
    return res;
  }

  Future<TranscriptionResult> _transcribeOffline(String filePath,
      {bool resumeFromPartial = false, String asrLang = 'ru'}) async {
    if (!GigaamService.isPrepared) {
      await _showModelPreparingDialog();
    }
    // Задача 036: если прошлый прогон был прерван (процесс убит системой),
    // предлагаем продолжить с последнего готового куска — текст уже
    // накопленных кусков не теряется и не расшифровывается заново.
    // Task 045: вход с карточки восстановления — продолжаем молча,
    // диалог не показываем (пользователь уже нажал [Продолжить]).
    var skipChunks = 0;
    var baseText = '';
    final partial = await TranscribeKeepAlive.readPartial();
    if (partial != null && mounted) {
      final sameFile =
          partial.$3 == null || partial.$3 == filePath;
      final resume = resumeFromPartial && sameFile
          ? true
          : await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(AppStrings.t('unfinished_title', context)),
                content: Text(AppStrings.tf('unfinished_body', ctx,
                    {'c': '${partial.$1}', 's': '${partial.$2.length}'})),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(AppStrings.t('start_over', context)),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(AppStrings.t('long_transcribe_continue', ctx)),
                  ),
                ],
              ),
            );
      if (resume == true) {
        skipChunks = partial.$1;
        baseText = partial.$2.trim();
      }
    }
    // Задача 036: расшифровка идёт минутами — поднимаем foreground-службу,
    // иначе при выключенном экране система убивает процесс и результат теряется.
    var keepAliveStarted = false;
    try {
      await TranscribeKeepAlive.start(AppStrings.t('keepalive_prep', context));
      keepAliveStarted = true;
    } catch (_) {}
    String? text;
    String? wav16k;
    final diagLines = <String>[];
    // Task 045: время старта задачи — фиксируем в состоянии на диске,
    // чтобы при перезапуске отличать «считалось сейчас» от «оборвалось».
    final jobStartedMs = DateTime.now().millisecondsSinceEpoch;
    // Окно работ появляется сразу и всё время показывает движение: этап, полоса
    // и секундомер. Раньше оно всплывало только после подготовки звука, поэтому
    // во время декодирования казалось, что ничего не происходит.
    final progress = ValueNotifier<(int, int)>((0, 0));
    final elapsed = ValueNotifier<int>(0);
    final stage = ValueNotifier<String>(AppStrings.t('stage_prep_audio', context));
    Timer? ticker;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.t('transcribing_now', context)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder<(int, int)>(
              valueListenable: progress,
              builder: (ctx, v, _) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                      value: v.$2 > 0 ? (v.$1 / v.$2).clamp(0.0, 1.0) : null),
                  const SizedBox(height: 10),
                  ValueListenableBuilder<int>(
                    valueListenable: elapsed,
                    builder: (ctx, sec, _) {
                      final shown = v.$2 > 0
                          ? AppStrings.tf('chunk_progress', ctx, {'d': '${v.$1}', 'a': '${v.$2}'}) + ' · ${((v.$1 / v.$2) * 100).round()}%'
                          : stage.value;
                      final mm = sec ~/ 60;
                      final ss = (sec % 60).toString().padLeft(2, '0');
                      return Text(AppStrings.tf('elapsed', ctx, {'t': '$mm:$ss'}).replaceFirst('{t}', '$mm:$ss').isEmpty ? '$shown · $mm:$ss' : '$shown · ${AppStrings.tf('elapsed', ctx, {'t': '$mm:$ss'})}',
                          style: const TextStyle(fontSize: 13));
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(AppStrings.t('on_device_note', context),
                style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
    ticker = Timer.periodic(const Duration(seconds: 1), (_) => elapsed.value++);
    var elapsedSec = 0;
    try {
      wav16k = await AudioConvert.toWav16k(filePath);
      stage.value = skipChunks > 0
          ? AppStrings.tf('stage_resume_skip', context, {'n': '$skipChunks'})
          : AppStrings.t('stage_transcribing', context);
      text = await GigaamService.transcribeWithGlossary(
        wav16k,
        language: asrLang,
        skipChunks: skipChunks,
        onProgress: (done, all) {
          progress.value = (done, all);
          // Задача 036: прогресс виден в уведомлении даже с погасшим экраном.
          final pct = all > 0 ? ((done / all) * 100).round() : 0;
          TranscribeKeepAlive.update(
              '${AppStrings.tf('chunk_progress', context, {'d': '$done', 'a': '$all'})} · $pct%');
        },
        onPartial: (done, all, partial) {
          // Задача 036: частичный результат сохраняем — при выгрузке не
          // потеряется. Текст = уже готовая база + новые куски; число
          // кусков абсолютное (с учётом пропущенных).
          // Задача 038: пишем и путь файла — стартовый баннер по нему
          // открывает нужную запись напрямую.
          // Task 045: пишем и состояние задачи (status/startedMs) — по
          // нему при перезапуске показываем карточку «прервана».
          final merged =
              baseText.isEmpty ? partial : '$baseText $partial'.trim();
          TranscribeKeepAlive.savePartial(done, merged,
              path: filePath, status: 'running', startedMs: jobStartedMs);
        },
        onLog: (line) => diagLines.add(line),
      );
      // Задача 036: дописываем текст пропущенных кусков из прерванного прогона.
      if (text != null && baseText.isNotEmpty) {
        final t = text!.trim();
        text = t.isEmpty ? baseText : '$baseText $t';
      }
    } finally {
      ticker?.cancel();
      elapsedSec = elapsed.value;
      if (mounted) Navigator.of(context).pop();
      progress.dispose();
      elapsed.dispose();
      stage.dispose();
      if (keepAliveStarted) await TranscribeKeepAlive.stop();
      // Task 045: почти весь файл — тишина (речь < 1% длины) — временной
      // WAV НЕ удаляем: складываем рядом с диагностикой в exports/,
      // иначе разобрать «почему пустой текст» без исходника невозможно.
      var speechPercent = -1.0;
      for (final line in diagLines) {
        final m = RegExp(r'речь=[\d.]+ c \(([\d.]+)% от файла\)')
            .firstMatch(line);
        if (m != null) {
          speechPercent = double.tryParse(m.group(1)!) ?? -1.0;
          break;
        }
      }
      // ВАЖНО (29.09.2026): если конвертация не потребовалась, wav16k — это и
      // есть исходный файл записи. Удалять/переносить его нельзя, иначе
      // теряется аудио и повторная расшифровка падает «Файл не найден».
      final isTempWav = wav16k != null && wav16k != filePath;
      if (isTempWav) {
        try {
          final f = File(wav16k!);
          if (await f.exists()) {
            if (speechPercent >= 0 && speechPercent < 1.0) {
              final ext = await getExternalStorageDirectory();
              if (ext != null) {
                final dir = Directory('${ext.path}/exports');
                await dir.create(recursive: true);
                final name = wav16k!.split(RegExp(r'[\\/]')).last;
                await f.rename('${dir.path}/$name');
                debugPrint('DictaPro: речь $speechPercent% (<1%) — '
                    'WAV сохранён в exports для разбора');
              }
            } else {
              // Задача 036: временный WAV сразу удаляем — раньше он оставался
              // навсегда, из-за чего папка приложения распухла до ~890 МБ.
              await f.delete();
            }
          }
        } catch (_) {}
      }
      await TranscribeKeepAlive.cleanupTempFiles();
      if (text != null && text.trim().isNotEmpty) {
        await TranscribeKeepAlive.clearPartial();
      }
    }
    // ДИАГНОСТИКА: сохраняем текст и цифры прогона в доступную папку приложения,
    // чтобы результат можно было проверить снаружи (файл не удаляем).
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null && text != null) {
        final dir = Directory('${ext.path}/exports');
        await dir.create(recursive: true);
        final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
        final f = File('${dir.path}/dictapro_$stamp.txt');
        final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        await f.writeAsString(
            '${AppStrings.tGlobal('diag_file_header')}\n'
            '${AppStrings.tfGlobal('diag_file_source', {'v': filePath})}\n'
            'wav16k: $wav16k\n'
            '${AppStrings.tfGlobal('diag_file_counts', {'c': '${text.length}', 'w': '$words'})}\n'
            '${AppStrings.tfGlobal('diag_file_time', {'v': '$elapsedSec'})}\n'
            '${diagLines.join('\n')}\n'
            '${AppStrings.tGlobal('diag_file_text_sep')}\n$text\n');
        debugPrint('DictaPro: выгружено ${f.path} (${text.length} символов, $words слов)');
      }
    } catch (e) {
      debugPrint('DictaPro: выгрузка не удалась: $e');
    }
    if (text == null || text.trim().isEmpty) {
      throw StateError('GigaAM не справился с записью');
    }
    return _gigaamResult(text, GigaamService.lastPartTimes,
        GigaamService.lastChunkWordCounts, baseText);
  }

  /// Модальный прогресс копирования модели из сборки во внутреннее
  /// хранилище при первом запуске. Отмены нет — без модели расшифровки нет.
  Future<void> _showModelPreparingDialog() async {
    final completer = Completer<void>();
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        var copied = 0;
        var total = 1;
        StateSetter? setDialogState;
        Timer.periodic(const Duration(milliseconds: 200), (timer) {
          if (!ctx.mounted || completer.isCompleted) {
            timer.cancel();
            return;
          }
          setDialogState?.call(() {});
        });
        GigaamService.ensureModelReady(onProgress: (c, t) {
          copied = c;
          total = t;
        }).then((_) {
          if (!completer.isCompleted) completer.complete();
          if (ctx.mounted) Navigator.of(ctx).pop();
        }).catchError((Object e) {
          if (!completer.isCompleted) completer.completeError(e);
          if (ctx.mounted) Navigator.of(ctx).pop();
        });
        return StatefulBuilder(
          builder: (ctx, setState) {
            setDialogState = setState;
            // Task 067: fast-follow — пока Play догружает пакет, показываем
            // скачивание; total==0 — размер ещё неизвестен, индетерминатно.
            final downloading = GigaamService.phase == 'download';
            final known = total > 0;
            final pct = known ? (copied / total).clamp(0.0, 1.0) : null;
            return AlertDialog(
              title: Text(
                downloading
                    ? AppStrings.t('model_prep_download', context)
                    : AppStrings.t('model_prep_title', context),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: pct),
                  const SizedBox(height: 8),
                  Text(
                    known
                        ? AppStrings.tf('model_prep_progress', context, {
                            'c': '${(copied / 1048576).round()}',
                            't': '${(total / 1048576).round()}',
                            'p': '${(pct! * 100).round()}'})
                        : AppStrings.t('model_prep_download', context),
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    await completer.future;
  }

  /// GigaAM выдаёт один текст — режем на сегменты по предложениям,
  /// чтобы редактор и статистика спикеров работали унифицированно.
  TranscriptionResult _gigaamResult(String text,
      [List<List<double>> times = const [],
      List<int> wordCounts = const [],
      String baseText = '']) {
    final sentences = text
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    // Настоящие таймкоды: раскладываем предложения по реальному интервалу речи
    // (от первого расшифрованного куска до последнего), пропорционально длине.
    // Это лечит «тап по фразе попадает в пустое начало записи».
    // Точная карта «слово → время»: у нас есть реальные интервалы кусков речи
    // и число слов в каждом. Если счёт сходится — раскладываем слова по кускам
    // и линейно внутри куска (тап по фразе попадает именно в её звук).
    // Если прогон был возобновлён («Продолжить»), первые куски не расшифрованы
    // заново — их слова лежат в baseText. Добавляем псевдо-кусок [0 .. первый
    // новый кусок], чтобы карта «слово → время» покрывала весь текст и не
    // съезжала на середину записи.
    var effTimes = times;
    var effCounts = wordCounts;
    if (baseText.trim().isNotEmpty && times.isNotEmpty) {
      final baseWords = baseText
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .length;
      if (baseWords > 0) {
        effTimes = [
          [0.0, times.first[0]],
          ...times,
        ];
        effCounts = [baseWords, ...wordCounts];
      }
    }
    final words =
        text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final totalWords = effCounts.fold<int>(0, (a, b) => a + b);
    final useWordMap = effTimes.isNotEmpty &&
        effCounts.isNotEmpty &&
        effCounts.length == effTimes.length &&
        totalWords == words.length;

    double timeOfWord(int k) {
      if (!useWordMap) return 0;
      if (k >= words.length) k = words.length - 1;
      var cum = 0;
      for (var i = 0; i < effCounts.length; i++) {
        final c = effCounts[i];
        if (k < cum + c) {
          final frac = c > 0 ? (k - cum) / c : 0.0;
          final s = effTimes[i][0];
          final e = effTimes[i][1];
          return s + (e - s) * frac;
        }
        cum += c;
      }
      return effTimes.last[1];
    }

    // Пропорция по длине — запасной вариант, если карта недоступна.
    var t0 = 0.0;
    var t1 = 0.0;
    if (times.isNotEmpty) {
      t0 = times.first[0];
      t1 = times.last[1];
    }
    final totalChars =
        sentences.fold<int>(0, (a, s) => a + (s.isEmpty ? 1 : s.length));
    final segs = <DialogueSegment>[];
    var acc = 0;
    var wordIdx = 0;
    for (final s in sentences) {
      final sw = s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      double a;
      double b;
      if (useWordMap) {
        a = timeOfWord(wordIdx);
        wordIdx += sw;
        b = timeOfWord(wordIdx);
      } else {
        a = totalChars > 0 ? t0 + (t1 - t0) * acc / totalChars : 0.0;
        acc += s.isEmpty ? 1 : s.length;
        b = totalChars > 0 ? t0 + (t1 - t0) * acc / totalChars : 0.0;
      }
      segs.add(DialogueSegment(
        speaker: 'Speaker 1',
        text: s,
        startTime: a,
        endTime: b,
      ));
    }
    if (segs.isEmpty) {
      segs.add(DialogueSegment(
        speaker: 'Speaker 1',
        text: text,
        startTime: 0,
        endTime: 0,
      ));
    }
    return TranscriptionResult(fullText: text, segments: segs);
  }

  void _showSnack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _toggleRecord() async {
    if (_isRecording) {
      await AudioService().stopRecording();
      _levelSub?.cancel();
      _levelSub = null;
      _stopTimer();
      setState(() {
        _isRecording = false;
        _level = 0;
      });
      _loadRecordings();

      // Full batch transcription после остановки записи
      // Task 053: длинные записи (>5 ч) — сначала честный диалог с оценкой,
      // до показа прогресс-диалога расшифровки.
      final recordingsPre = AudioService().getAllRecordings();
      if (recordingsPre.isNotEmpty &&
          !await _confirmLongTranscription(
              recordingsPre.first.durationMs as int? ?? 0)) {
        return;
      }
      // Task 054: лимит бесплатной расшифровки действует и на пакетный запуск.
      if (recordingsPre.isNotEmpty &&
          !await _checkTranscribeLimit(
              recordingsPre.first.durationMs as int? ?? 0)) {
        return;
      }
      _showTranscribingDialog();
      try {
        final recordings = AudioService().getAllRecordings();
        if (recordings.isNotEmpty) {
          final latest = recordings.first;
          final asrLangRec = await _chooseAsrLang();
          if (asrLangRec == null) return;
          final onlineText = await _onlineTranscript(latest.filePath);
          final result = onlineText == null
              ? await _transcribeOffline(latest.filePath, asrLang: asrLangRec)
              : null;
          final fullText = onlineText ?? result!.fullText;

          latest.transcription = fullText;
          latest.segments = result != null
              ? result.segments.map((s) => s.toMap()).toList()
              : null;
          latest.tags = TagService.extractTags(fullText);
          // Task 057: саммари ТОЛЬКО на устройстве (BYOK-облако отменено).
          // Никаких ключей, никакой отправки текста. Недоступно/пусто —
          // честная строка, а не молчание.
          _opStage.value = AppStrings.t('summary_computing', context);
          try {
            final local = (await EnhancedSummaryService.generateSummaryAsync(
                    fullText))
                .formatted
                .trim();
            latest.summary =
                local.isEmpty ? AppStrings.t('summary_failed', context) : local;
          } catch (_) {
            latest.summary = AppStrings.t('summary_failed', context);
          }
          latest.decisions = SummaryService.getDecisions(fullText);
          await AudioService().updateRecording(latest);
          // Task 054: трата минут фиксируется после УСПЕШНОЙ расшифровки.
          await _recordTranscribeUsage(latest.durationMs as int? ?? 0);
          // Task 056: готово в фоне → уведомление + плашка при возврате.
          if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
            _finishedInBackground = true;
          }
          await LocalNotify.instance.showTranscriptionDone();
          _loadRecordings();
        }
      } catch (e) {
        // Батч не удался — запись остаётся без транскрипции, сообщаем честно
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppStrings.tf('transcribe_failed', context, {'e': '$e'}))),
          );
        }
      } finally {
        _hideTranscribingDialog();
      }
    } else {
      // «Термины этой записи» → глоссарий GigaAM (task 019; раньше — VOSK AddWord)
      final hotwords = HotwordsStorage.parse(_hotwordsController.text);
      if (hotwords.isNotEmpty) {
        await HotwordsStorage.remember(hotwords);
        _recentHotwords = await HotwordsStorage.recent();
      }
      await AudioService().startRecording();
      _startTimer();
      setState(() => _isRecording = true);
      // Живой уровень с микрофона: полоса двигается по реальному звуку.
      _levelSub?.cancel();
      _levelSub = AudioService().amplitudeLevel().listen((v) {
        if (!mounted) return;
        setState(() {
          _level = v > _level ? v : (_level * 0.72 + v * 0.28);
        });
      });
    }
  }

  void _playRecording(rec) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerPage(recording: rec),
      ),
    );
  }

  Future<void> _deleteRecording(String id) async {
    await AudioService().deleteRecording(id);
    _loadRecordings();
  }

  /// Task 045: [resumeFromPartial] — вход с карточки восстановления:
  /// расшифровка продолжается с куска M автоматически, без диалога
  /// «продолжить/начать заново».
  // ---------- Task 054: монетизация (разовая покупка) ----------

  /// Paywall: лимит исчерпан → «Купить полную версию» / «Восстановить покупку».
  Future<void> _showPaywall() async {
    final used = await UsageLimitService.instance.usedMinutesToday();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.limitReachedTitle(ctx)),
        content: Text(AppStrings.limitReachedBody(ctx,
            used: used, limit: UsageLimitService.dailyMinutesLimit)),
        actions: [
          // Task 065: ссылка на полный экран подписки (тарифы и пакеты).
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SubscriptionPage()),
              );
            },
            child: Text(AppStrings.t('sub_all_plans', ctx)),
          ),
          TextButton(
            onPressed: () {
              PurchaseService.instance.restore();
              Navigator.pop(ctx);
            },
            child: Text(AppStrings.restorePurchase(ctx)),
          ),
          FilledButton(
            onPressed: () async {
              final ok = await PurchaseService.instance.buyFullUnlock();
              if (!ok && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(AppStrings.storeUnavailable(context))));
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(AppStrings.buyFull(ctx)),
          ),
        ],
      ),
    );
  }

  /// Дневной лимит бесплатной расшифровки (15 мин/день, task 054).
  /// true — можно расшифровывать (полная версия или лимит не исчерпан).
  Future<bool> _checkTranscribeLimit(int durationMs) async {
    if (PurchaseService.instance.unlocked.value) return true;
    final ok = await UsageLimitService.instance.canTranscribe(durationMs);
    if (!ok) {
      await _showPaywall();
      return false;
    }
    return true;
  }

  /// Фиксация траты минут после УСПЕШНОЙ расшифровки (только бесплатный режим).
  Future<void> _recordTranscribeUsage(int durationMs) async {
    if (PurchaseService.instance.unlocked.value) return;
    await UsageLimitService.instance.recordUsage(durationMs);
  }

  /// Task 053: запись длиннее 5 часов расшифровывается часами — предупреждаем
  /// заранее с оценкой времени (из замера на устройстве, см. AppStrings).
  /// true — можно запускать; false — пользователь отменил.
  static const _kLongRecordingMs = 5 * 3600000; // 5 часов

  Future<bool> _confirmLongTranscription(int durationMs) async {
    if (durationMs <= _kLongRecordingMs) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.longTranscribeTitle(ctx)),
        content: Text(AppStrings.longTranscribeBody(
          ctx,
          duration: AppStrings.humanDuration(durationMs,
              lang: Localizations.localeOf(ctx).languageCode),
          estimate: AppStrings.transcribeEstimate(durationMs,
              lang: Localizations.localeOf(ctx).languageCode),
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppStrings.longTranscribeCancel(ctx)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppStrings.longTranscribeContinue(ctx)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// «3аново»: сбрасываем прошлый результат и запускаем распознавание ещё раз.
  Future<void> _retranscribe(rec) async {
    rec.transcription = null;
    rec.segments = null;
    rec.summary = null;
    rec.tags = null;
    rec.decisions = null;
    await AudioService().updateRecording(rec);
    // Частичный прогресс НЕ стираем: если прошлый прогон обрывался (вылет),
    // штатный поток предложит «Продолжить с куска N / Начать заново».
    await _transcribeRecording(rec);
  }

  Future<void> _transcribeRecording(rec,
      {bool resumeFromPartial = false}) async {
    // Путь может содержать старый UUID контейнера (iOS меняет его при
    // переустановке) — вычисляем актуальный.
    final filePath = await AudioService.resolveFilePath(rec.filePath);
    final srcFile = File(filePath);
    if (!await srcFile.exists()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.t('audio_lost_banner', context)),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }
    if (await srcFile.length() == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.t('rec_empty_file_msg', context)),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }

    // Task 053: длинные записи (>5 ч) — сначала честный диалог с оценкой.
    if (!await _confirmLongTranscription(rec.durationMs as int? ?? 0)) {
      return;
    }

    final asrLang = await _chooseAsrLang();
    if (asrLang == null) return;

    _showTranscribingDialog();

    try {
      final onlineText = await _onlineTranscript(filePath);
      final result = onlineText == null
          ? await _transcribeOffline(filePath,
              resumeFromPartial: resumeFromPartial, asrLang: asrLang)
          : null;

      final punctuatedText = onlineText ?? result!.fullText;

      rec.transcription = punctuatedText;
      rec.segments = result != null
          ? result.segments.map((s) => s.toMap()).toList()
          : null;
      rec.tags = TagService.extractTags(punctuatedText);
      // Сохраняем распознанный текст ДО сборки итогов: даже если следующий шаг
      // упадёт или пользователь уйдёт из диалога — результат уже на диске.
      await AudioService().updateRecording(rec);
      // Task 057: саммари ТОЛЬКО на устройстве (BYOK-облако отменено).
      _opStage.value = AppStrings.t('summary_computing', context);
      try {
        final local = (await EnhancedSummaryService.generateSummaryAsync(
                punctuatedText))
            .formatted
            .trim();
        rec.summary = local.isEmpty ? AppStrings.t('summary_failed', context) : local;
      } catch (_) {
        rec.summary = AppStrings.t('summary_failed', context);
      }
      rec.decisions = SummaryService.getDecisions(punctuatedText);
      rec.speakerStats = result != null
          ? SummaryService.getSpeakerStats(result.segments.map((s) => s.toMap()).toList())
          : null;
      await AudioService().updateRecording(rec);
      await _recordTranscribeUsage(rec.durationMs as int? ?? 0);
      // Task 056: готово в фоне → уведомление + плашка при возврате.
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        _finishedInBackground = true;
      }
      await LocalNotify.instance.showTranscriptionDone();

      _hideTranscribingDialog();
      _openDialogueEditor(rec);
    } on PlatformException catch (e) {
      _hideTranscribingDialog();
      final msg = e.message ?? AppStrings.t('platform_error', context);
      final details = e.details?.toString() ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.tf('error_prefix', context, {'m': '$msg${details.isNotEmpty ? " ($details)" : ""}'})),
          backgroundColor: Colors.red.shade900,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      _hideTranscribingDialog();
      final s = '$e';
      final friendly = (s.contains('Decoded audio is empty') ||
              s.contains('No audio data decoded'))
          ? AppStrings.t('rec_decode_failed_msg', context)
          : (s.contains('No such file') ||
                  s.contains('FileSystemException'))
              ? AppStrings.t('audio_lost_banner', context)
              : s.contains('GigaAM не справился')
                  ? AppStrings.t('rec_no_speech_msg', context)
                  : AppStrings.tf('transcribe_error', context, {'e': s});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendly),
          backgroundColor: Colors.red.shade900,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }



  void _openDialogueEditor(rec) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DialogueEditor(recording: rec),
      ),
    ).then((saved) {
      if (saved == true) {
        _loadRecordings();
      }
    });
  }

  Future<void> _importFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
      allowCompression: false,
    );

    if (result == null || result.files.isEmpty) return;

    int successCount = 0;
    int failCount = 0;

    final allowedExts = ['wav', 'mp3', 'm4a', 'aac', 'ogg', 'flac', 'wma'];

    for (final picked in result.files) {
      final sourcePath = picked.path;
      final fileBytes = picked.bytes;
      
      final ext = (picked.extension ?? picked.name.split('.').last).toLowerCase();
      if (!allowedExts.contains(ext)) {
        failCount++;
        continue;
      }

      try {
        final dir = await getApplicationDocumentsDirectory();
        final id = DateTime.now().millisecondsSinceEpoch.toString();
        final destPath = '${dir.path}/imported_${id}_${successCount}.$ext';
        
        if (sourcePath != null && sourcePath.isNotEmpty) {
          await File(sourcePath).copy(destPath);
        } else if (fileBytes != null && fileBytes.isNotEmpty) {
          await File(destPath).writeAsBytes(fileBytes);
        } else {
          failCount++;
          continue;
        }

        final file = File(destPath);
        final size = await file.length();
        final now = DateTime.now();

        int durationMs = 0;
        try {
          final player = AudioPlayer();
          await player.setFilePath(destPath);
          final dur = await player.durationStream.firstWhere(
            (d) => d != null && d.inMilliseconds > 0,
            orElse: () => null,
          );
          if (dur != null) {
            durationMs = dur.inMilliseconds;
          }
          await player.dispose();
        } catch (_) {}

        final recording = Recording(
          id: now.millisecondsSinceEpoch.toString() + '_$successCount',
          filePath: destPath,
          createdAt: now,
          durationMs: durationMs,
          fileSize: size,
          title: picked.name,
        );

        await AudioService().updateRecording(recording);
        successCount++;
      } catch (e) {
        failCount++;
      }
    }

    _loadRecordings();

    if (mounted) {
      String msg = AppStrings.tf('imported', context, {'n': '$successCount'});
      if (failCount > 0) msg = AppStrings.tf('imported_errors', context, {'n': '$successCount', 'e': '$failCount'});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  void _exportRecording(rec) {
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.t('export_format_title', context)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.text_snippet, color: Colors.green),
              title: Text(AppStrings.t('export_txt', context)),
              onTap: () => Navigator.pop(ctx, 'txt'),
            ),
            ListTile(
              leading: const Icon(Icons.code, color: Colors.blue),
              title: Text(AppStrings.t('export_html', context)),
              onTap: () => Navigator.pop(ctx, 'html'),
            ),
            ListTile(
              leading: const Icon(Icons.content_copy),
              title: Text(AppStrings.t('export_copy', context)),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: Text(AppStrings.t('export_pdf', context)),
              onTap: () => Navigator.pop(ctx, 'pdf'),
            ),
          ],
        ),
      ),
    ).then((format) {
      if (format == null || !mounted) return;

      switch (format) {
        case 'txt':
          final text = ExportService.formatTranscriptTxt(rec);
          ExportService.shareFile(text, '${rec.title ?? "transcript"}.txt');
          break;
        case 'html':
          final text = ExportService.formatTranscriptHtml(rec);
          ExportService.shareFile(text, '${rec.title ?? "transcript"}.html');
          break;
        case 'pdf':
          _showExportingDialog();
          ExportService.exportAsPdf(rec).then((path) {
            _hideExportingDialog();
            Share.shareXFiles([XFile(path)], text: AppStrings.t('share_pdf_caption', context));
          }).catchError((e) {
            _hideExportingDialog();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppStrings.tf('export_pdf_error', context, {'e': '$e'}))),
              );
            }
          });
          break;
        case 'copy':
          ExportService.copyToClipboard(rec.transcription ?? '');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(AppStrings.t('text_copied', context))),
            );
          }
          break;
      }
    });
  }

  Future<void> _showShareOptions(rec) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.t('share_title', context)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (rec.transcription != null && rec.transcription!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.text_snippet, color: Colors.blue),
                title: Text(AppStrings.t('share_transcript', context)),
                onTap: () => Navigator.pop(ctx, 'text'),
              ),
            ListTile(
              leading: const Icon(Icons.audio_file, color: Colors.purple),
              title: Text(AppStrings.t('share_audio', context)),
              onTap: () => Navigator.pop(ctx, 'audio'),
            ),
          ],
        ),
      ),
    );

    if (choice == 'text') {
      // Показываем диалог формата экспорта для текста
      final format = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppStrings.t('send_text_title', context)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.text_snippet, color: Colors.green),
                title: Text(AppStrings.t('export_txt', context)),
                onTap: () => Navigator.pop(ctx, 'txt'),
              ),
              ListTile(
                leading: const Icon(Icons.code, color: Colors.blue),
                title: Text(AppStrings.t('export_html', context)),
                onTap: () => Navigator.pop(ctx, 'html'),
              ),
              ListTile(
                leading: const Icon(Icons.content_copy),
                title: Text(AppStrings.t('export_copy', context)),
                onTap: () => Navigator.pop(ctx, 'copy'),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: Text(AppStrings.t('export_pdf', context)),
                onTap: () => Navigator.pop(ctx, 'pdf'),
              ),
            ],
          ),
        ),
      );

      if (format == null || !mounted) return;

      switch (format) {
        case 'txt':
          final text = ExportService.formatTranscriptTxt(rec);
          ExportService.shareFile(text, '${rec.title ?? "transcript"}.txt');
          break;
        case 'html':
          final text = ExportService.formatTranscriptHtml(rec);
          ExportService.shareFile(text, '${rec.title ?? "transcript"}.html');
          break;
        case 'pdf':
          _showExportingDialog();
          ExportService.exportAsPdf(rec).then((path) {
            _hideExportingDialog();
            Share.shareXFiles([XFile(path)], text: AppStrings.t('share_pdf_caption', context));
          }).catchError((e) {
            _hideExportingDialog();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppStrings.tf('export_pdf_error', context, {'e': '$e'}))),
              );
            }
          });
          break;
        case 'copy':
          ExportService.copyToClipboard(rec.transcription ?? '');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(AppStrings.t('text_copied', context))),
            );
          }
          break;
      }
    } else if (choice == 'audio') {
      ExportService.shareAudioFile(await AudioService.resolveFilePath(rec.filePath));
    }
  }

  void _openSummaryPage(rec) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SummaryPage(
          recording: RecordingDetailsModel.fromRecording(rec.toMap()),
          // Task 059: онлайн-итоги сохраняем текстом в запись (Hive).
          onSave: (text) async {
            final latest = await AudioService().getRecordingById(rec.id);
            if (latest == null) return;
            latest.summary = text;
            await AudioService().updateRecording(latest);
          },
        ),
      ),
    );
  }

  void _shareTranscript(rec) {
    final text = ExportService.formatTranscript(rec);
    ExportService.shareText(text);
  }

  Future<void> _toggleFavorite(rec) async {
    rec.isFavorite = !rec.isFavorite;
    await AudioService().updateRecording(rec);
    _loadRecordings();
  }

  Future<void> _renameRecording(rec) async {
    final controller = TextEditingController(text: rec.title);

    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.t('rename_title', context)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: AppStrings.t('rename_hint', context),
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.t('long_transcribe_cancel', context)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(AppStrings.t('save', context)),
          ),
        ],
      ),
    );

    if (newTitle != null && newTitle.isNotEmpty) {
      rec.title = newTitle;
      await AudioService().updateRecording(rec);
      _loadRecordings();
    }
  }

  Widget _highlightSearchInPreview(String text) {
    if (_searchQuery.isEmpty) {
      return Text(
        text,
        style: const TextStyle(color: Colors.green, fontSize: 12),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = _searchQuery.toLowerCase();
    final index = lowerText.indexOf(lowerQuery);

    if (index == -1) {
      return Text(
        text,
        style: const TextStyle(color: Colors.green, fontSize: 12),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    int start = (index - 15).clamp(0, text.length);
    int end = (index + _searchQuery.length + 15).clamp(0, text.length);

    String preview = text.substring(start, end);
    if (start > 0) preview = '...$preview';
    if (end < text.length) preview = '$preview...';

    final spans = <TextSpan>[];
    final lowerPreview = preview.toLowerCase();
    int searchIndex = lowerPreview.indexOf(lowerQuery);

    if (searchIndex > 0) {
      spans.add(TextSpan(
        text: preview.substring(0, searchIndex),
        style: const TextStyle(color: Colors.green, fontSize: 12),
      ));
    }

    spans.add(TextSpan(
      text: preview.substring(searchIndex, searchIndex + _searchQuery.length),
      style: const TextStyle(
        color: Colors.black,
        fontSize: 12,
        backgroundColor: Colors.yellow,
        fontWeight: FontWeight.bold,
      ),
    ));

    if (searchIndex + _searchQuery.length < preview.length) {
      spans.add(TextSpan(
        text: preview.substring(searchIndex + _searchQuery.length),
        style: const TextStyle(color: Colors.green, fontSize: 12),
      ));
    }

    return RichText(
      text: TextSpan(children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  /// Task 056: актуальный статус после возврата из фона.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _finishedInBackground) {
      _finishedInBackground = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppStrings.t('transcription_done_bg', context)),
        ));
        _loadRecordings();
      }
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _levelSub?.cancel();
    _timer?.cancel();
    _pulseController.dispose();
    _searchController.dispose();
    _hotwordsController.dispose();
    _opStage.dispose();
    AudioService().dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRecordings;

    return DictaBackground(
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: AppStrings.t('search_hint', context),
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              )
            : DictaBrand(
                title: widget.tab == 1
                    ? AppStrings.t('nav_texts', context)
                    : (widget.tab == 2
                        ? AppStrings.t('nav_summaries', context)
                        : null),
                subtitle: widget.tab == 1
                    ? AppStrings.t('texts_subtitle', context)
                    : (widget.tab == 2
                        ? AppStrings.t('summaries_subtitle', context)
                        : AppStrings.splashSlogan(context)),
              ),
        centerTitle: !_isSearching,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        leading: _isSearching
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _isSearching = false;
                    _searchQuery = '';
                    _searchController.clear();
                  });
                },
              )
            : null,
        actions: [
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => setState(() => _isSearching = true),
            ),
        ],
      ),
      body: Column(
        children: [
          if (widget.tab == 0)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.mint.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.mint.withValues(alpha: 0.22)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: AppColors.mint, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Text(_engineLabel,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_isRecording) ...[
                  // Живой уровень звука: заполняется по реальной амплитуде с микрофона.
                  SizedBox(
                    width: 190,
                    height: 8,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _level.clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.12),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(AppColors.record),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                GestureDetector(
                  onTap: _toggleRecord,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: _isRecording ? 84 : 88,
                    height: _isRecording ? 84 : 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isRecording
                          ? Theme.of(context).colorScheme.surface
                          : AppColors.record,
                      border: Border.all(
                        color: _isRecording
                            ? AppColors.record
                            : Colors.transparent,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.record.withOpacity(0.35),
                          blurRadius: 26,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Icon(
                      _isRecording ? Icons.stop : Icons.mic,
                      size: _isRecording ? 34 : 36,
                      color: _isRecording ? AppColors.record : AppColors.redInk,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _isRecording ? AppStrings.t('stop_recording', context) : AppStrings.t('start_recording', context),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: _isRecording ? AppColors.red : AppColors.mint,
                        fontSize: 12.5,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  _fmtTime(_recordSeconds ~/ 10),
                  style: TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: _isRecording
                        ? AppColors.record
                        : Theme.of(context).colorScheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 12),
                if (AudioService().sleepDurationMinutes != null)
                  Text(
                    AppStrings.tf('timer_active', context, {'m': '${AudioService().sleepDurationMinutes}'}),
                    style: const TextStyle(color: Colors.amber, fontSize: 12),
                  ),
                if (AudioService().sleepDurationMinutes != null)
                  const SizedBox(height: 4),

                if (!_isRecording) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _hotwordsController,
                    decoration: InputDecoration(
                      hintText:
                          AppStrings.t('hotwords_hint', context),
                      hintStyle: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                      isDense: true,
                      filled: true,
                      fillColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: Icon(Icons.spellcheck,
                          size: 18, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (_recentHotwords.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final w in _recentHotwords)
                            GestureDetector(
                              onTap: () {
                                final cur = _hotwordsController.text;
                                if (!cur
                                    .toLowerCase()
                                    .contains(w.toLowerCase())) {
                                  _hotwordsController.text =
                                      cur.trim().isEmpty ? w : '$cur, $w';
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: DictaTokens.of(context).surface2,
                                  borderRadius: BorderRadius.circular(99),
                                  border: Border.all(
                                      color: DictaTokens.of(context).line),
                                ),
                                child: Text(w,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: DictaTokens.of(context).ink2)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                // (нижняя кнопка записи убрана — одна большая кнопка выше)
                const SizedBox(height: 8),
                if (!_isRecording)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: _showSleepTimerDialog,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: DictaTokens.of(context).surface2,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                              color: DictaTokens.of(context).line),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.timer_outlined,
                                size: 14, color: DictaTokens.of(context).ink3),
                            const SizedBox(width: 5),
                            Text(
                              AudioService().sleepDurationMinutes != null
                                  ? AppStrings.tf('timer_min', context, {'m': '${AudioService().sleepDurationMinutes}'})
                                  : AppStrings.t('sleep_timer', context),
                              style: TextStyle(
                                  color: DictaTokens.of(context).ink2,
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Task 045: карточка восстановления видна сразу, пока не выбрано
          // действие; живая плашка «Идёт расшифровка» важнее — заменяет её.
          if (_liveActive)
            _liveStatusCard()
          else if (_recoveryJob != null)
            _recoveryCard(),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: Row(
                      children: [
                        DictaChip(AppStrings.t('filter_all', context),
                            selected: _quickFilter == 0,
                            onTap: () => setState(() => _quickFilter = 0)),
                        const SizedBox(width: 7),
                        DictaChip(AppStrings.t('filter_today', context),
                            selected: _quickFilter == 1,
                            onTap: () => setState(() => _quickFilter = 1)),
                        const SizedBox(width: 7),
                        DictaChip(AppStrings.t('filter_queued', context),
                            selected: _quickFilter == 2,
                            onTap: () => setState(() => _quickFilter = 2)),
                        const Spacer(),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: AppStrings.t('import_tooltip', context),
                          icon: Icon(Icons.upload_file_outlined,
                              size: 20, color: DictaTokens.of(context).ink3),
                          onPressed: _importFile,
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: AppStrings.t('favorites_tooltip', context),
                          icon: Icon(
                              _showFavoritesOnly
                                  ? Icons.star
                                  : Icons.star_border,
                              size: 20,
                              color: _showFavoritesOnly
                                  ? AppColors.gold
                                  : DictaTokens.of(context).ink3),
                          onPressed: () => setState(
                              () => _showFavoritesOnly = !_showFavoritesOnly),
                        ),
                        PopupMenuButton<SortOption>(
                          icon: Icon(Icons.sort,
                              color: DictaTokens.of(context).ink3, size: 20),
                          tooltip: AppStrings.t('sort_tooltip', context),
                          onSelected: (option) {
                            setState(() => _sortOption = option);
                            _saveSortPreference(option);
                          },
                          itemBuilder: (context) => SortOption.values.map((option) {
                            return PopupMenuItem(
                              value: option,
                              child: Row(
                                children: [
                                  if (_sortOption == option)
                                    Icon(Icons.check, size: 16, color: DictaTokens.of(context).mint)
                                  else
                                    const SizedBox(width: 16),
                                  const SizedBox(width: 8),
                                  Text(AppStrings.t(option.label, context)),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? _emptyState()
                        : ListView.builder(
                            padding: EdgeInsets.only(
                                left: 16, right: 16, top: 8, bottom: MediaQuery.of(context).padding.bottom + 16),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final rec = filtered[index];
                              final hasTranscription =
                                  rec.transcription != null &&
                                      rec.transcription!.isNotEmpty;
                              final dateStr =
                                  DateFormat('dd.MM').format(rec.createdAt);
                              final timeStr =
                                  DateFormat('HH:mm').format(rec.createdAt);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Theme.of(context).dividerColor,
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 12, 16, 0),
                                      child: Row(
                                        children: [
                                          GestureDetector(
                                            onTap: () => _renameRecording(rec),
                                            child: ConstrainedBox(
                                              constraints:
                                                  const BoxConstraints(maxWidth: 210),
                                              child: Text(
                                                rec.title ?? '$dateStr $timeStr',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurface,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          GestureDetector(
                                            onTap: () => _toggleFavorite(rec),
                                            child: Icon(
                                              rec.isFavorite
                                                  ? Icons.star
                                                  : Icons.star_border,
                                              size: 20,
                                              color: rec.isFavorite
                                                  ? AppColors.gold
                                                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            '${_fmtDuration(rec.durationMs)} • ${_fmtSize(rec.fileSize)}',
                                            style: TextStyle(
                                              fontFamily: 'JetBrains Mono',
                                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (hasTranscription && widget.tab != 2)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            16, 8, 16, 0),
                                        child: _highlightSearchInPreview(
                                            rec.transcription!),
                                      ),
                                    if (rec.tags != null && rec.tags!.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                                        child: Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: rec.tags!.map<Widget>((tag) =>
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: DictaTokens.of(context).surface2,
                                                borderRadius: BorderRadius.circular(99),
                                                border: Border.all(
                                                  color: DictaTokens.of(context).line,
                                                  width: 1,
                                                ),
                                              ),
                                              child: Text(
                                                '#$tag',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: DictaTokens.of(context).ink3,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ).toList(),
                                        ),
                                      ),
                                    // AI Summary Preview (на вкладке «Итоги» —
                                    // единственный превью-блок; на «Текстах» скрыт)
                                    if (hasTranscription && widget.tab != 1)
                                      GestureDetector(
                                        onTap: () => _openSummaryPage(rec),
                                        child: Container(
                                          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: DictaTokens.of(context).mint.withValues(alpha: 0.07),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: DictaTokens.of(context).mint.withValues(alpha: 0.24)),
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Icon(Icons.auto_awesome, size: 14, color: DictaTokens.of(context).mint),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  (rec.summary != null && rec.summary!.isNotEmpty)
                                                      ? rec.summary!
                                                      : (rec.transcription!.length > 100
                                                          ? '${rec.transcription!.substring(0, 100)}...'
                                                          : rec.transcription!),
                                                  style: TextStyle(
                                                    color: DictaTokens.of(context).ink2,
                                                    fontSize: 12,
                                                    height: 1.35,
                                                  ),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),

                                    Padding(
                                      padding:
                                          const EdgeInsets.fromLTRB(4, 4, 4, 8),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceEvenly,
                                        children: [
                                          _ActionButton(
                                            icon: hasTranscription
                                                ? Icons.text_snippet
                                                : Icons.transcribe,
                                            color: DictaTokens.of(context).ink2,
                                            label: hasTranscription
                                                ? AppStrings.t('btn_dialog', context)
                                                : AppStrings.t('btn_to_text', context),
                                            onTap: () => hasTranscription
                                                ? _openDialogueEditor(rec)
                                                : _transcribeRecording(rec),
                                          ),
                                          if (hasTranscription &&
                                              (rec.transcription?.split(' ').length ?? 0) >= 100)
                                            _ActionButton(
                                              icon: Icons.auto_awesome,
                                              color: DictaTokens.of(context).mint,
                                              label: AppStrings.t('btn_gist', context),
                                              onTap: () => _openSummaryPage(rec),
                                            ),
                                          if (hasTranscription)
                                            _ActionButton(
                                              icon: Icons.refresh,
                                              color: DictaTokens.of(context).ink2,
                                              label: AppStrings.t('btn_redo', context),
                                              onTap: () => _retranscribe(rec),
                                            ),
                                          _ActionButton(
                                            icon: Icons.share,
                                            color: DictaTokens.of(context).ink2,
                                            label: AppStrings.t('btn_send', context),
                                            onTap: () => _showShareOptions(rec),
                                          ),
                                          _ActionButton(
                                            icon: Icons.play_arrow,
                                            color: DictaTokens.of(context).ink2,
                                            label: AppStrings.t('btn_listen', context),
                                            onTap: () => _playRecording(rec),
                                          ),
                                          _ActionButton(
                                            icon: Icons.delete_outline,
                                            color: Colors.red.withOpacity(0.7),
                                            label: AppStrings.t('btn_delete', context),
                                            onTap: () =>
                                                _deleteRecording(rec.id),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: color.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
