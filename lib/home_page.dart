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
import 'theme/app_theme.dart';
import 'models/transcription.dart';
import 'services/ai_summary_service.dart';
import 'services/stt_provider.dart';
import 'services/gigaam_service.dart';
import 'services/audio_convert.dart';
import 'services/glossary_service.dart';
import 'services/online_transcribe_service.dart';
import 'services/keep_alive.dart';
import 'dialogue_editor.dart';
import 'tag_service.dart';
import 'app_strings.dart';
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
        return 'Дата (новые)';
      case SortOption.dateOldest:
        return 'Дата (старые)';
      case SortOption.nameAsc:
        return 'Имя (А-Я)';
      case SortOption.durationLongest:
        return 'Длительность (длинные)';
      case SortOption.durationShortest:
        return 'Длительность (короткие)';
    }
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
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
  Timer? _timer;
  late AnimationController _pulseController;
  final _searchController = TextEditingController();
  final _hotwordsController = TextEditingController();
  List<String> _recentHotwords = [];
  // Одна строка состояния распознавания (task 019, дизайн V3):
  // движок один — GigaAM v3, модель вложена в сборку.
  final String _engineLabel = 'Распознавание: на устройстве · модель внутри';

  @override
  void initState() {
    super.initState();
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
                const Text('Идёт расшифровка',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  [
                    if (_liveStartedMs > 0)
                      'идёт ${(((DateTime.now().millisecondsSinceEpoch - _liveStartedMs) / 60000).floor())} мин',
                    'готово кусков: $_liveChunks',
                    'символов: $_liveChars',
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

  /// Задача 038: стартовый баннер «Найдена незаконченная расшифровка».
  /// Читает и старый plain-text формат (сборка 51) — в нём нет номера
  /// куска, тогда предлагаем хотя бы сохранить текст.
  Future<void> _checkUnfinishedTranscription() async {
    final saved = await TranscribeKeepAlive.readPartial();
    if (!mounted || saved == null) return;
    final chars = saved.$2.trim().length;
    if (chars == 0) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showMaterialBanner(MaterialBanner(
      content: Text(
        'Найдена незаконченная расшифровка: $chars символов'
        '${saved.$1 > 0 ? ' (оборвалась на куске ${saved.$1})' : ''}',
      ),
      actions: [
        TextButton(
          onPressed: () async {
            messenger.hideCurrentMaterialBanner();
            // Продолжить: если знаем файл и нашли его запись — идём
            // полным путём (расшифровка → сохранение в запись → саммари);
            // диалог «продолжить с куска N» всплывёт внутри расшифровки.
            final path = saved.$3;
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
                  await _transcribeRecording(rec);
                  return;
                }
              } catch (_) {}
            }
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text(
                    'Откройте ту же запись и запустите расшифровку — предложим продолжить с места обрыва.'),
              ));
            }
          },
          child: const Text('Продолжить'),
        ),
        TextButton(
          onPressed: () async {
            messenger.hideCurrentMaterialBanner();
            // Сохраняем найденный текст отдельной записью — он не потеряется.
            try {
              final now = DateTime.now();
              final rec = Recording(
                id: now.millisecondsSinceEpoch.toString(),
                filePath: '',
                createdAt: now,
                durationMs: 0,
                fileSize: 0,
                title: 'Прерванная расшифровка',
                transcription: saved.$2.trim(),
              );
              await AudioService().updateRecording(rec);
              _loadRecordings();
              await TranscribeKeepAlive.clearPartial();
            } catch (_) {}
          },
          child: const Text('Сохранить текст'),
        ),
        TextButton(
          onPressed: () async {
            messenger.hideCurrentMaterialBanner();
            await TranscribeKeepAlive.clearPartial();
          },
          child: const Text('Удалить'),
        ),
      ],
    ));
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
    if (_searchQuery.isNotEmpty) {
      list = list.where((rec) {
        final text = rec.transcription?.toLowerCase() ?? '';
        final title = (rec.title ?? '').toLowerCase();
        final name = 'Запись ${DateFormat('dd.MM HH:mm').format(rec.createdAt)}'
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
              isSearch ? Icons.search_off : Icons.mic_none,
              size: 56,
              color: scheme.onSurface.withOpacity(0.25),
            ),
            const SizedBox(height: 14),
            Text(
              isSearch ? 'Ничего не нашлось' : 'Пока ни одной записи',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isSearch
                  ? 'Попробуйте другое слово или очистите поиск.'
                  : 'Нажмите большую кнопку «Начать запись» — или импортируйте '
                      'готовый файл (mp3, m4a, wav) и расшифруйте его.',
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
        title: const Text('Таймер остановки'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.timer_off),
              title: const Text('Без таймера'),
              onTap: () => Navigator.pop(ctx, 0),
            ),
            ListTile(
              leading: const Icon(Icons.timer),
              title: const Text('15 минут'),
              onTap: () => Navigator.pop(ctx, 15),
            ),
            ListTile(
              leading: const Icon(Icons.timer),
              title: const Text('30 минут'),
              onTap: () => Navigator.pop(ctx, 30),
            ),
            ListTile(
              leading: const Icon(Icons.timer),
              title: const Text('60 минут'),
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
  final ValueNotifier<String> _opStage = ValueNotifier('Расшифровка…');

  // Живая плашка: показываем, что расшифровка идёт (даже если интерфейс
  // перезапускался и окно прогресса потерялось).
  bool _liveActive = false;
  int _liveChunks = 0;
  int _liveChars = 0;
  String? _livePath;
  int _liveStartedMs = 0;
  String _liveStage = '';
  Timer? _liveTimer;


  void _showTranscribingDialog() {
    // Task 041: повторный вход (двойной тап, батч + ручной запуск)
    // не должен запускать вторую конвертацию и второй диалог.
    if (_isTranscribing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Расшифровка уже идёт — дождитесь окончания')),
      );
      return;
    }
    _isTranscribing = true;
    _opStage.value = 'Расшифровка…';
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
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Создание PDF...'),
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Онлайн-распознавание…'), duration: Duration(seconds: 2)));
      }
      return await OnlineTranscribeService.transcribe(path,
          provider: provider, apiKey: key);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Онлайн не удался, остаёмся офлайн: $e'),
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
        title: const Text('Вы выходите из офлайн-режима'),
        content: Text(
            'Обычно все записи остаются только на этом устройстве. '
            'Для точного распознавания звук этой записи будет отправлен '
            'на сервер ($providerTitle). Больше ничего не передаётся.',
            style: const TextStyle(fontSize: 14, height: 1.4)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Остаться офлайн')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Распознать онлайн')),
        ],
      ),
    );
  }

  /// Офлайн-транскрибация (task 019): движок один — GigaAM v3, модель
  /// вложена в сборку. Не-WAV и не 16 кГц конвертируем нативным каналом,
  /// дальше стандартный путь (VAD + изолят) без изменений.
  /// При первом запуске показываем прогресс локального копирования модели
  /// («Подготовка модели: X%») — без сети, без возможности отменить.
  Future<TranscriptionResult> _transcribeOffline(String filePath) async {
    if (!GigaamService.isPrepared) {
      await _showModelPreparingDialog();
    }
    // Задача 036: если прошлый прогон был прерван (процесс убит системой),
    // предлагаем продолжить с последнего готового куска — текст уже
    // накопленных кусков не теряется и не расшифровывается заново.
    var skipChunks = 0;
    var baseText = '';
    final partial = await TranscribeKeepAlive.readPartial();
    if (partial != null && mounted) {
      final cont = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Незавершённая расшифровка'),
          content: Text(
              'В прошлый раз распознание оборвалось на куске ${partial.$1} '
              '(${partial.$2.length} символов текста уже готово).\n\n'
              'Продолжить с этого места или начать заново?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Начать заново'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Продолжить'),
            ),
          ],
        ),
      );
      if (cont == true) {
        skipChunks = partial.$1;
        baseText = partial.$2.trim();
      }
    }
    // Задача 036: расшифровка идёт минутами — поднимаем foreground-службу,
    // иначе при выключенном экране система убивает процесс и результат теряется.
    var keepAliveStarted = false;
    try {
      await TranscribeKeepAlive.start('Расшифровка: готовлю аудио…');
      keepAliveStarted = true;
    } catch (_) {}
    String? text;
    String? wav16k;
    final diagLines = <String>[];
    // Окно работ появляется сразу и всё время показывает движение: этап, полоса
    // и секундомер. Раньше оно всплывало только после подготовки звука, поэтому
    // во время декодирования казалось, что ничего не происходит.
    final progress = ValueNotifier<(int, int)>((0, 0));
    final elapsed = ValueNotifier<int>(0);
    final stage = ValueNotifier<String>('Готовим аудио (декодирование)…');
    Timer? ticker;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Расшифровка'),
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
                          ? 'Кусок ${v.$1} из ${v.$2} · ${((v.$1 / v.$2) * 100).round()}%'
                          : stage.value;
                      final mm = sec ~/ 60;
                      final ss = (sec % 60).toString().padLeft(2, '0');
                      return Text('$shown · прошло $mm:$ss',
                          style: const TextStyle(fontSize: 13));
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            const Text('Считается на устройстве — можно не держать экран открытым',
                style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
    ticker = Timer.periodic(const Duration(seconds: 1), (_) => elapsed.value++);
    try {
      wav16k = await AudioConvert.toWav16k(filePath);
      stage.value = skipChunks > 0
          ? 'Продолжаем: пропускаем $skipChunks готовых кусков…'
          : 'Расшифровка идёт…';
      text = await GigaamService.transcribeWithGlossary(
        wav16k,
        skipChunks: skipChunks,
        onProgress: (done, all) {
          progress.value = (done, all);
          // Задача 036: прогресс виден в уведомлении даже с погасшим экраном.
          final pct = all > 0 ? ((done / all) * 100).round() : 0;
          TranscribeKeepAlive.update('Кусок $done из $all · $pct%');
        },
        onPartial: (done, all, partial) {
          // Задача 036: частичный результат сохраняем — при выгрузке не
          // потеряется. Текст = уже готовая база + новые куски; число
          // кусков абсолютное (с учётом пропущенных).
          // Задача 038: пишем и путь файла — стартовый баннер по нему
          // открывает нужную запись напрямую.
          final merged =
              baseText.isEmpty ? partial : '$baseText $partial'.trim();
          TranscribeKeepAlive.savePartial(done, merged, path: filePath);
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
      if (mounted) Navigator.of(context).pop();
      progress.dispose();
      elapsed.dispose();
      stage.dispose();
      if (keepAliveStarted) await TranscribeKeepAlive.stop();
      // Задача 036: временный WAV сразу удаляем — раньше он оставался
      // навсегда, из-за чего папка приложения распухла до ~890 МБ.
      if (wav16k != null) {
        try {
          final f = File(wav16k);
          if (await f.exists()) await f.delete();
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
            '=== ДиктаПро: диагностика прогона ===\n'
            'источник: $filePath\n'
            'wav16k: $wav16k\n'
            'символов: ${text.length}; слов: $words\n'
            '${diagLines.join('\n')}\n'
            '=== ТЕКСТ ===\n$text\n');
        debugPrint('DictaPro: выгружено ${f.path} (${text.length} символов, $words слов)');
      }
    } catch (e) {
      debugPrint('DictaPro: выгрузка не удалась: $e');
    }
    if (text == null || text.trim().isEmpty) {
      throw StateError('GigaAM не справился с записью');
    }
    return _gigaamResult(text);
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
            final pct = total > 0 ? (copied / total).clamp(0.0, 1.0) : 0.0;
            return AlertDialog(
              title: const Text('Подготовка модели'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: pct),
                  const SizedBox(height: 8),
                  Text(
                    '${(copied / 1048576).round()} из ${(total / 1048576).round()} МБ · ${(pct * 100).round()}%',
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
  TranscriptionResult _gigaamResult(String text) {
    final sentences = text
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final segs = <DialogueSegment>[];
    for (final s in sentences) {
      segs.add(DialogueSegment(
        speaker: 'Speaker 1',
        text: s,
        startTime: 0,
        endTime: 0,
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
          final onlineText = await _onlineTranscript(latest.filePath);
          final result = onlineText == null
              ? await _transcribeOffline(latest.filePath)
              : null;
          final fullText = onlineText ?? result!.fullText;

          latest.transcription = fullText;
          latest.segments = result != null
              ? result.segments.map((s) => s.toMap()).toList()
              : null;
          latest.tags = TagService.extractTags(fullText);
          final useCloudSummary = await AiSummaryService.cloudEnabled();
          // Task 034: облачное саммари с бюджетом 40 с; по таймауту —
          // честное сообщение и переход на локальное (оно в изоляте).
          String? cloudSummary;
          if (useCloudSummary) {
            cloudSummary =
                await AiSummaryService.generateWithTimeout(fullText);
            if (cloudSummary == null &&
                AiSummaryService.lastError == 'timeout' &&
                mounted) {
              _showSnack('Облако не ответило за 40 с — считаю на устройстве');
            }
          }
          _opStage.value = 'Считаю саммари…';
          latest.summary = cloudSummary ??
              (await EnhancedSummaryService.generateSummaryAsync(fullText))
                  .formatted;
          latest.decisions = SummaryService.getDecisions(fullText);
          await AudioService().updateRecording(latest);
          _loadRecordings();
        }
      } catch (e) {
        // Батч не удался — запись остаётся без транскрипции, сообщаем честно
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Расшифровка не удалась: $e')),
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
          duration: AppStrings.humanDuration(durationMs),
          estimate: AppStrings.transcribeEstimate(durationMs),
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

  Future<void> _transcribeRecording(rec) async {
    // Путь может содержать старый UUID контейнера (iOS меняет его при
    // переустановке) — вычисляем актуальный.
    final filePath = await AudioService.resolveFilePath(rec.filePath);
    if (!await File(filePath).exists()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Файл не найден: $filePath'),
          backgroundColor: Colors.red.shade900,
        ),
      );
      return;
    }

    // Task 053: длинные записи (>5 ч) — сначала честный диалог с оценкой.
    if (!await _confirmLongTranscription(rec.durationMs as int? ?? 0)) {
      return;
    }

    _showTranscribingDialog();

    try {
      final onlineText = await _onlineTranscript(filePath);
      final result = onlineText == null
          ? await _transcribeOffline(filePath)
          : null;

      final punctuatedText = onlineText ?? result!.fullText;

      rec.transcription = punctuatedText;
      rec.segments = result != null
          ? result.segments.map((s) => s.toMap()).toList()
          : null;
      rec.tags = TagService.extractTags(punctuatedText);
      // Task 034: облако с бюджетом 40 с, таймаут → честное сообщение и
      // локальное саммари в изоляте (интерфейс не замерзает).
      final useCloudSummary2 = await AiSummaryService.cloudEnabled();
      String? cloudSummary2;
      if (useCloudSummary2) {
        cloudSummary2 =
            await AiSummaryService.generateWithTimeout(punctuatedText);
        if (cloudSummary2 == null &&
            AiSummaryService.lastError == 'timeout' &&
            mounted) {
          _showSnack('Облако не ответило за 40 с — считаю на устройстве');
        }
      }
      _opStage.value = 'Считаю саммари…';
      rec.summary = cloudSummary2 ??
          (await EnhancedSummaryService.generateSummaryAsync(punctuatedText))
              .formatted;
      rec.decisions = SummaryService.getDecisions(punctuatedText);
      rec.speakerStats = result != null
          ? SummaryService.getSpeakerStats(result.segments.map((s) => s.toMap()).toList())
          : null;
      await AudioService().updateRecording(rec);
      await _recordTranscribeUsage(rec.durationMs as int? ?? 0);

      _hideTranscribingDialog();
      _openDialogueEditor(rec);
    } on PlatformException catch (e) {
      _hideTranscribingDialog();
      final msg = e.message ?? 'Ошибка платформы';
      final details = e.details?.toString() ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: $msg${details.isNotEmpty ? " ($details)" : ""}'),
          backgroundColor: Colors.red.shade900,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      _hideTranscribingDialog();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка транскрибации: $e'),
          backgroundColor: Colors.red.shade900,
          duration: const Duration(seconds: 5),
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
      String msg = 'Импортировано: $successCount';
      if (failCount > 0) msg += ', ошибок: $failCount';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  void _exportRecording(rec) {
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Формат экспорта'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.text_snippet, color: Colors.green),
              title: const Text('TXT — текст с таймкодами'),
              onTap: () => Navigator.pop(ctx, 'txt'),
            ),
            ListTile(
              leading: const Icon(Icons.code, color: Colors.blue),
              title: const Text('HTML — красивый документ'),
              onTap: () => Navigator.pop(ctx, 'html'),
            ),
            ListTile(
              leading: const Icon(Icons.content_copy),
              title: const Text('Скопировать текст'),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text('PDF — документ'),
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
            Share.shareXFiles([XFile(path)], text: 'Транскрипция записи в PDF');
          }).catchError((e) {
            _hideExportingDialog();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Ошибка PDF: $e')),
              );
            }
          });
          break;
        case 'copy':
          ExportService.copyToClipboard(rec.transcription ?? '');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Текст скопирован')),
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
        title: const Text('Поделиться'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (rec.transcription != null && rec.transcription!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.text_snippet, color: Colors.blue),
                title: const Text('Текст транскрипции'),
                onTap: () => Navigator.pop(ctx, 'text'),
              ),
            ListTile(
              leading: const Icon(Icons.audio_file, color: Colors.purple),
              title: const Text('Аудиозапись'),
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
          title: const Text('Отправить текст'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.text_snippet, color: Colors.green),
                title: const Text('TXT — текст с таймкодами'),
                onTap: () => Navigator.pop(ctx, 'txt'),
              ),
              ListTile(
                leading: const Icon(Icons.code, color: Colors.blue),
                title: const Text('HTML — красивый документ'),
                onTap: () => Navigator.pop(ctx, 'html'),
              ),
              ListTile(
                leading: const Icon(Icons.content_copy),
                title: const Text('Скопировать текст'),
                onTap: () => Navigator.pop(ctx, 'copy'),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: const Text('PDF — документ'),
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
            Share.shareXFiles([XFile(path)], text: 'Транскрипция записи в PDF');
          }).catchError((e) {
            _hideExportingDialog();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Ошибка PDF: $e')),
              );
            }
          });
          break;
        case 'copy':
          ExportService.copyToClipboard(rec.transcription ?? '');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Текст скопирован')),
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
        title: const Text('Переименовать'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Название записи...',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Сохранить'),
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
  void dispose() {
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

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Поиск по транскрипциям...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              )
            : const Center(
                child: Text('ДиктаПро',
                    style: TextStyle(fontWeight: FontWeight.bold))),
        centerTitle: !_isSearching,
        elevation: 0,
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
          if (!_isSearching) ...[
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white),
              tooltip: 'Настройки',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.folder_open),
              onPressed: _importFile,
            ),
            IconButton(
              icon: Icon(_showFavoritesOnly ? Icons.star : Icons.star_border),
              color: _showFavoritesOnly ? Colors.amber : null,
              onPressed: () {
                setState(() {
                  _showFavoritesOnly = !_showFavoritesOnly;
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => setState(() => _isSearching = true),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                Text(
                  _isRecording ? '● Идет запись...' : 'Нажмите для записи',
                  style: TextStyle(
                    color: _isRecording ? Colors.red : Colors.white54,
                    fontSize: 14,
                    fontWeight:
                        _isRecording ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: Color(0xFF5FBF8B), shape: BoxShape.circle),
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
                    width: _isRecording ? 108 : 132,
                    height: _isRecording ? 108 : 132,
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
                      size: _isRecording ? 44 : 52,
                      color: _isRecording ? AppColors.record : Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _isRecording ? 'Остановить запись' : 'Начать запись',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  _fmtTime(_recordSeconds ~/ 10),
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: _isRecording
                        ? AppColors.record
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 12),
                if (AudioService().sleepDurationMinutes != null)
                  Text(
                    'Таймер: ${AudioService().sleepDurationMinutes} мин',
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
                          'Термины этой записи (имена, аббревиатуры — через запятую)',
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
                      prefixIcon: const Icon(Icons.spellcheck,
                          size: 18, color: Colors.white38),
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
                                  color: Colors.white.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(w,
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.white54)),
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
                  GestureDetector(
                    onTap: _showSleepTimerDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.timer, size: 16, color: Colors.white54),
                          const SizedBox(width: 4),
                          Text(
                            AudioService().sleepDurationMinutes != null
                                ? '${AudioService().sleepDurationMinutes} мин'
                                : 'Таймер сна',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_liveActive) _liveStatusCard(),
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
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    child: Row(
                      children: [
                        const Icon(Icons.library_music,
                            size: 20, color: Colors.white54),
                        const SizedBox(width: 8),
                        Text(
                          _searchQuery.isEmpty
                              ? (_showFavoritesOnly ? 'Избранное (${filtered.length})' : 'Записи (${_recordings.length})')
                              : 'Найдено: ${filtered.length}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white70,
                          ),
                        ),
                        const Spacer(),
                        PopupMenuButton<SortOption>(
                          icon: const Icon(Icons.sort, color: Colors.white54, size: 20),
                          tooltip: 'Сортировка',
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
                                    const Icon(Icons.check, size: 16, color: Colors.green)
                                  else
                                    const SizedBox(width: 16),
                                  const SizedBox(width: 8),
                                  Text(option.label),
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
                                  borderRadius: BorderRadius.circular(18),
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
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                    .withOpacity(0.15),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                rec.title ??
                                                    '$dateStr $timeStr',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
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
                                                  ? Colors.amber
                                                  : Colors.white30,
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            '${_fmtDuration(rec.durationMs)} • ${_fmtSize(rec.fileSize)}',
                                            style: const TextStyle(
                                              color: Colors.white38,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (hasTranscription)
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
                                                color: Colors.amber.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: Colors.amber.withOpacity(0.3),
                                                  width: 1,
                                                ),
                                              ),
                                              child: Text(
                                                '#$tag',
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.amber,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ).toList(),
                                        ),
                                      ),
                                    // AI Summary Preview
                                    if (hasTranscription)
                                      GestureDetector(
                                        onTap: () => _openSummaryPage(rec),
                                        child: Container(
                                          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.cyan.withOpacity(0.08),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: Colors.cyan.withOpacity(0.2)),
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Icon(Icons.auto_awesome, size: 14, color: Colors.cyan),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  (rec.summary != null && rec.summary!.isNotEmpty)
                                                      ? rec.summary!
                                                      : (rec.transcription!.length > 100
                                                          ? '${rec.transcription!.substring(0, 100)}...'
                                                          : rec.transcription!),
                                                  style: const TextStyle(
                                                    color: Colors.white60,
                                                    fontSize: 12,
                                                    height: 1.3,
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
                                            color: Colors.green,
                                            label: hasTranscription
                                                ? 'Диалог'
                                                : 'В текст',
                                            onTap: () => hasTranscription
                                                ? _openDialogueEditor(rec)
                                                : _transcribeRecording(rec),
                                          ),
                                          if (hasTranscription &&
                                              (rec.transcription?.split(' ').length ?? 0) >= 100)
                                            _ActionButton(
                                              icon: Icons.auto_awesome,
                                              color: Colors.cyan,
                                              label: 'Суть',
                                              onTap: () => _openSummaryPage(rec),
                                            ),
                                          _ActionButton(
                                            icon: Icons.share,
                                            color: Colors.blue,
                                            label: 'Отправить',
                                            onTap: () => _showShareOptions(rec),
                                          ),
                                          _ActionButton(
                                            icon: Icons.play_arrow,
                                            color: Colors.white,
                                            label: 'Слушать',
                                            onTap: () => _playRecording(rec),
                                          ),
                                          _ActionButton(
                                            icon: Icons.delete_outline,
                                            color: Colors.red.withOpacity(0.7),
                                            label: 'Удалить',
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
