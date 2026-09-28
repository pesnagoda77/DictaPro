import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'app_strings.dart';
import 'models/recording_details_model.dart';
import 'services/ai_hours_service.dart';
import 'services/enhanced_summary_service.dart';
import 'services/online_summary_service.dart';
import 'theme/app_theme.dart';
import 'utils.dart';
import 'widgets/operation_progress.dart';

/// Экран «Итоги» (V3): конспект записи по образцу экрана 11
/// docs/design/v3_redesign_canvas.html.
///
/// Локальные и онлайн-итоги хранятся отдельно; переключатель
/// «Локально / Онлайн» выбирает, что показать. Онлайн расходует
/// ИИ-часы (повторный показ из кэша — бесплатно), локальные — офлайн.
class SummaryPage extends StatefulWidget {
  final RecordingDetailsModel recording;

  /// Task 059: сохранить готовый текст итогов обратно в запись (Hive).
  final Future<void> Function(String text)? onSave;

  const SummaryPage({
    super.key,
    required this.recording,
    this.onSave,
  });

  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage> {
  bool _showFullText = false;

  /// Итоги по источникам: локальные и онлайн не затирают друг друга.
  SummaryResult? _localResult;
  SummaryResult? _onlineResult;

  bool _isLoadingSummary = false;
  bool _localFailed = false;

  // Task 059: онлайн-итоги и счётчик ИИ-часов.
  bool _onlineBusy = false;
  bool _onlineFailed = false;
  bool _onlineWasUsed = false;
  bool _canSpend = true;
  String _hoursLabel = '';

  /// 0 — локально, 1 — онлайн.
  int _mode = 0;

  // Task 034: этап операции для индикатора с секундомером.
  final ValueNotifier<String> _stage = ValueNotifier('Готовим текст…');

  bool get _hasTranscript =>
      widget.recording.transcript != null &&
      widget.recording.transcript!.isNotEmpty;

  int get _audioMs => widget.recording.duration?.inMilliseconds ?? 0;

  @override
  void dispose() {
    _stage.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _refreshHoursLabel();
    if (widget.recording.summary != null &&
        widget.recording.summary!.isNotEmpty &&
        widget.recording.summary != 'Нет доступного резюме') {
      _generateSummary();
    }
  }

  // Task 034: саммари считается в изоляте — главный поток свободен,
  // счётчик тикает, пользователь может уйти с экрана и вернуться.
  Future<void> _generateSummary() async {
    if (!_hasTranscript) return;

    setState(() {
      _isLoadingSummary = true;
      _localFailed = false;
      _mode = 0;
    });
    _stage.value = AppStrings.t('summary_computing', context);
    try {
      final summary = await EnhancedSummaryService.generateSummaryAsync(
        widget.recording.transcript!,
        onProgress: (done, total) {
          // Промежуточный прогресс для длинных текстов (по частям).
          _stage.value = total > 1
              ? AppStrings.tf('summary_part', context, {'d': '$done', 't': '$total'})
              : AppStrings.t('summary_computing', context);
        },
      );
      // Экран могли закрыть, пока изолят считал — setState только если живы.
      if (!mounted) return;
      setState(() {
        _localResult = summary;
        _isLoadingSummary = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingSummary = false;
        _localFailed = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.t('summary_failed_snack', context))),
      );
    }
  }

  Future<void> _refreshHoursLabel() async {
    final label = await AiHoursService.instance.balanceLabel();
    final canSpend = await AiHoursService.instance.canSpend(_audioMs);
    if (mounted) {
      setState(() {
        _hoursLabel = label;
        _canSpend = canSpend;
      });
    }
  }

  /// Task 059: онлайн-итоги. Gate для бесплатных: без подписки и без
  /// пакетов кнопка неактивна, серверная авторизация — второй рубеж
  /// (проверка «бесплатный не может отправить ничего» — перехватом).
  Future<void> _generateOnlineSummary() async {
    final transcript = widget.recording.transcript;
    if (transcript == null || transcript.isEmpty || _onlineBusy) return;

    final canSpend = await AiHoursService.instance.canSpend(_audioMs);
    if (!mounted) return;
    if (!canSpend) {
      _showSnack(AppStrings.t('online_summary_no_hours', context));
      return;
    }

    // Предупреждение перед отправкой текста на сервер (ТЗ, точный смысл).
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.t('online_summary_warning_title', context)),
        content: Text(AppStrings.t('online_summary_warning_body', context)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppStrings.t('online_summary_cancel', context)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppStrings.t('online_summary_send', context)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _onlineBusy = true;
      _onlineFailed = false;
      _mode = 1;
    });
    _stage.value = AppStrings.t('online_summary_stage', context);
    try {
      final res = await OnlineSummaryService.instance.summarize(
        fileId: widget.recording.filePath ?? widget.recording.title,
        text: transcript,
        audioMs: _audioMs,
        lang: Localizations.localeOf(context).languageCode,
      );
      if (!mounted) return;
      if (res == null) {
        setState(() => _onlineFailed = true);
        _showSnack(AppStrings.t('online_summary_failed', context));
        return;
      }
      setState(() {
        _onlineBusy = false;
        _onlineWasUsed = true;
        _onlineResult = SummaryResult(
          title: AppStrings.t('online_summary_title', context),
          type: TextType.general,
          points: res.text.split('\n').where((e) => e.trim().isNotEmpty).toList(),
          fullText: transcript,
        );
      });
      _showSnack(res.fromCache
          ? AppStrings.t('online_summary_from_cache', context)
          : AppStrings.tf('online_summary_spent', context,
              {'h': _fmtHours(res.aiHoursSpent)}));
      await _refreshHoursLabel();
      await widget.onSave?.call(res.text);
    } finally {
      if (mounted) setState(() => _onlineBusy = false);
    }
  }

  String _fmtHours(double h) => h.toStringAsFixed(1);

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DictaBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            _buildHeader(context),
            const SizedBox(height: 5),
            _buildMetaLine(context),
            const SizedBox(height: 12),
            if (_hasTranscript) ...[
              _buildToggle(context),
              const SizedBox(height: 12),
            ],
            ..._buildContent(context),
          ],
        ),
      ),
    );
  }

  // ============ Шапка ============

  Widget _buildHeader(BuildContext context) {
    final tk = DictaTokens.of(context);
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.recording.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Text(
                'конспект из текста записи',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: tk.mint,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _airPill(context, 'Экспорт', () => _shareContent(context)),
        const SizedBox(width: 2),
        IconButton(
          onPressed: () => _copyToClipboard(context),
          icon: Icon(Icons.copy_rounded, size: 18, color: tk.ink3),
        ),
      ],
    );
  }

  Widget _buildMetaLine(BuildContext context) {
    final tk = DictaTokens.of(context);
    final recording = widget.recording;
    return Padding(
      padding: const EdgeInsets.only(left: 50),
      child: Text(
        '${formatDuration(recording.duration ?? Duration.zero)} · ${formatDateTime(recording.dateTime ?? DateTime.now())}',
        style: tk.mono(11, FontWeight.w600, tk.ink3),
      ),
    );
  }

  Widget _airPill(BuildContext context, String text, VoidCallback onTap) {
    final tk = DictaTokens.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tk.line),
        ),
        child: Text(text, style: TextStyle(fontSize: 10, color: tk.ink2)),
      ),
    );
  }

  // ============ Переключатель «Локально / Онлайн» ============

  Widget _buildToggle(BuildContext context) {
    final tk = DictaTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: tk.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tk.line),
      ),
      child: Row(
        children: [
          _toggleSeg(context, index: 0, label: 'Локально', sub: 'без интернета'),
          _toggleSeg(context, index: 1, label: 'Онлайн', sub: 'точнее · ИИ-часы'),
        ],
      ),
    );
  }

  Widget _toggleSeg(
    BuildContext context, {
    required int index,
    required String label,
    required String sub,
  }) {
    final tk = DictaTokens.of(context);
    final on = _mode == index;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => setState(() => _mode = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: on ? tk.mint : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: on ? AppColors.mintInk : tk.ink3,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                sub,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: on
                      ? AppColors.mintInk.withValues(alpha: 0.75)
                      : tk.ink3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============ Содержимое ============

  List<Widget> _buildContent(BuildContext context) {
    final children = <Widget>[];

    if (!_hasTranscript) {
      children.add(_statePlate(
        context,
        icon: Icons.text_snippet_outlined,
        title: AppStrings.t('summary_title', context),
        body: AppStrings.t('no_transcript', context),
      ));
      return children;
    }

    final busy = _mode == 1 ? _onlineBusy : _isLoadingSummary;
    if (busy) {
      children.add(_progressPlate(context));
    } else if (_mode == 1) {
      final r = _onlineResult;
      if (r != null) {
        children.addAll(_blocksFor(context, r));
      } else if (_onlineFailed) {
        children.add(_statePlate(
          context,
          icon: Icons.cloud_off_outlined,
          title: AppStrings.t('online_summary_title', context),
          body: AppStrings.t('online_summary_failed', context),
          gold: true,
        ));
      } else if (!_canSpend) {
        children.add(_statePlate(
          context,
          icon: Icons.hourglass_bottom_rounded,
          title: AppStrings.t('online_summary_title', context),
          body: AppStrings.t('online_summary_no_hours', context),
          gold: true,
        ));
      } else {
        children.add(_statePlate(
          context,
          icon: Icons.cloud_outlined,
          title: AppStrings.t('online_summary_title', context),
          body: AppStrings.t('summary_press_button', context),
        ));
      }
    } else {
      final r = _localResult;
      final saved = widget.recording.summary;
      if (r != null) {
        children.addAll(_blocksFor(context, r));
      } else if (_localFailed) {
        children.add(_statePlate(
          context,
          icon: Icons.error_outline_rounded,
          title: AppStrings.t('summary_title', context),
          body: AppStrings.t('summary_failed', context),
          gold: true,
        ));
      } else if (saved != null &&
          saved.isNotEmpty &&
          saved != AppStrings.t('no_summary_yet', context)) {
        final lines = saved
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        children.add(_blk(
          context,
          title: AppStrings.t('summary_card_title', context),
          lines: [for (final l in lines) _richLi(context, l)],
        ));
      } else {
        children.add(_statePlate(
          context,
          icon: Icons.auto_awesome_outlined,
          title: AppStrings.t('summary_title', context),
          body: AppStrings.t('summary_press_button', context),
        ));
      }
    }

    children.add(_buildFullTextSection(context));
    children.add(_notePlate(context));
    children.add(const SizedBox(height: 2));
    children.add(_buildActions(context));
    return children;
  }

  /// Раскладывает пункты итогов по трём блокам: «О чём договорились»,
  /// «Задачи» и «Цифры и даты». Служебные маркеры сервиса (буллеты,
  /// квадратики, вопросы, идеи, даты) в текст не попадают.
  List<Widget> _blocksFor(BuildContext context, SummaryResult result) {
    final agreed = <String>[];
    final tasks = <String>[];
    final numbers = <String>[];
    final seen = <String>{};

    void add(List<String> bucket, String raw) {
      final t = raw.trim();
      if (t.isEmpty) return;
      if (seen.add(t.toLowerCase())) bucket.add(t);
    }

    bool numbersHeader(String h) =>
        h.contains('финанс') ||
        h.contains('сумм') ||
        h.contains('срок') ||
        h.contains('дат') ||
        h.contains('цифр') ||
        h.contains('стои') ||
        h.contains('бюджет');

    bool tasksHeader(String h) => h.contains('делать') || h.contains('задач');

    final ideaMark = '\u{1F4A1}';
    final dateMark = '\u{1F4C5}';
    var header = '';

    for (final raw in result.points) {
      final indent = raw.startsWith('  ');
      var t = raw.trim();
      if (t.isEmpty) continue;

      final isHeader = !indent &&
          !t.startsWith('•') &&
          !t.startsWith('□') &&
          !t.startsWith('?') &&
          !t.startsWith('Q:') &&
          !t.startsWith(ideaMark) &&
          !t.startsWith(dateMark);

      if (isHeader && t.endsWith(':') && t.length <= 42) {
        header = t.toLowerCase();
        continue;
      }

      var bucket = agreed;
      if (t.startsWith('□')) {
        bucket = tasks;
        t = t.substring(1).trim();
      } else if (t.startsWith(dateMark)) {
        bucket = numbers;
        t = t.substring(1).trim();
      } else {
        if (t.startsWith(ideaMark)) {
          t = t.substring(1).trim();
        } else if (t.startsWith('Q:')) {
          t = t.substring(2).trim();
        } else if (t.startsWith('?') || t.startsWith('•')) {
          t = t.substring(1).trim();
        } else if (t.startsWith('- ') ||
            t.startsWith('— ') ||
            t.startsWith('– ')) {
          t = t.substring(2).trim();
        }
        if (tasksHeader(header)) {
          bucket = tasks;
        } else if (numbersHeader(header)) {
          bucket = numbers;
        }
      }
      add(bucket, t);
    }

    for (final a in result.actionItems) {
      add(tasks, a);
    }
    for (final c in result.contacts) {
      add(agreed, c);
    }
    for (final d in [...result.deadlines, ...result.amounts, ...result.dates]) {
      add(numbers, d);
    }

    final blocks = <Widget>[];
    if (agreed.isNotEmpty) {
      blocks.add(_blk(
        context,
        title: 'О ЧЁМ ДОГОВОРИЛИСЬ',
        lines: [for (final t in agreed) _richLi(context, t)],
      ));
    }
    if (tasks.isNotEmpty) {
      blocks.add(_blk(
        context,
        title: 'ЗАДАЧИ',
        lines: [for (final t in tasks) _taskLi(context, t)],
      ));
    }
    if (numbers.isNotEmpty) {
      blocks.add(_blk(
        context,
        title: 'ЦИФРЫ И ДАТЫ',
        lines: [for (final t in numbers) _monoLi(context, t)],
      ));
    }
    if (blocks.isEmpty) {
      blocks.add(_statePlate(
        context,
        icon: Icons.auto_awesome_outlined,
        title: AppStrings.t('summary_title', context),
        body: AppStrings.t('summary_press_button', context),
      ));
    }
    return blocks;
  }

  // ============ Блоки и пункты ============

  Widget _blk(BuildContext context, {required String title, required List<Widget> lines}) {
    final tk = DictaTokens.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tk.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tk.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: tk.mint,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 7),
          ...lines,
        ],
      ),
    );
  }

  Widget _richLi(BuildContext context, String text) {
    final tk = DictaTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text.rich(
        _richText(text, tk, TextStyle(fontSize: 12, height: 1.5, color: tk.ink2)),
      ),
    );
  }

  Widget _taskLi(BuildContext context, String text) {
    final tk = DictaTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 13,
            height: 13,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: tk.mint, width: 1.5),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              _richText(text, tk, TextStyle(fontSize: 12, height: 1.5, color: tk.ink2)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _monoLi(BuildContext context, String text) {
    final tk = DictaTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(
        text,
        style: tk.mono(11, FontWeight.w600, tk.ink2).copyWith(height: 1.55),
      ),
    );
  }

  /// Жирный префикс до «:» или « — » — как в макете (.li b).
  TextSpan _richText(String text, DictaTokens tk, TextStyle base) {
    final m = RegExp(r'^([^:]{1,48}):\s+(\S.*)$').firstMatch(text);
    if (m != null && RegExp(r'[A-Za-zА-Яа-яЁё]').hasMatch(m.group(1)!)) {
      return TextSpan(
        style: base,
        children: [
          TextSpan(
            text: '${m.group(1)}:',
            style: base.copyWith(color: tk.ink, fontWeight: FontWeight.w600),
          ),
          TextSpan(text: ' ${m.group(2)}'),
        ],
      );
    }
    final dash = text.indexOf(' — ');
    if (dash > 0 && dash <= 48) {
      final rest = text.substring(dash + 3).trim();
      if (rest.isNotEmpty) {
        return TextSpan(
          style: base,
          children: [
            TextSpan(
              text: text.substring(0, dash),
              style: base.copyWith(color: tk.ink, fontWeight: FontWeight.w600),
            ),
            TextSpan(text: ' — $rest'),
          ],
        );
      }
    }
    return TextSpan(text: text, style: base);
  }

  // ============ Плашки ============

  Widget _progressPlate(BuildContext context) {
    final tk = DictaTokens.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tk.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tk.mint.withValues(alpha: 0.24)),
      ),
      child: Center(child: OperationProgressView(stage: _stage)),
    );
  }

  Widget _statePlate(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
    bool gold = false,
  }) {
    final tk = DictaTokens.of(context);
    final c = gold ? tk.gold : tk.mint;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tk.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tk.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.withValues(alpha: 0.24)),
            ),
            child: Icon(icon, size: 17, color: c),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(fontSize: 12, color: tk.ink2, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _notePlate(BuildContext context) {
    final tk = DictaTokens.of(context);
    const base = TextStyle(fontSize: 11.5, height: 1.5);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tk.mint.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              style: base.copyWith(color: tk.ink2),
              children: [
                const TextSpan(
                  text:
                      'Онлайн-итоги считаются на сервере за ИИ-часы и кэшируются: повторный показ — ',
                ),
                TextSpan(
                  text: 'бесплатно',
                  style: base.copyWith(color: tk.ink, fontWeight: FontWeight.w600),
                ),
                const TextSpan(text: '. Локальные итоги не используют интернет.'),
              ],
            ),
          ),
          if (_hoursLabel.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _hoursLabel,
                    style: tk.mono(10.5, FontWeight.w600, tk.ink3),
                  ),
                ),
                if (_onlineWasUsed)
                  TextButton(
                    onPressed: _refreshHoursLabel,
                    child: Text(AppStrings.t('online_summary_refresh', context)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ============ Полный текст и действия ============

  Widget _buildFullTextSection(BuildContext context) {
    final tk = DictaTokens.of(context);
    final transcript = widget.recording.transcript;
    if (transcript == null || transcript.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tk.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tk.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _showFullText = !_showFullText),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Полный текст',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Icon(
                  _showFullText
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: tk.ink3,
                ),
              ],
            ),
          ),
          if (_showFullText) ...[
            const SizedBox(height: 8),
            Text(
              transcript,
              style: tk.mono(11.5, FontWeight.w500, tk.ink2).copyWith(height: 1.6),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final busy = _isLoadingSummary || _onlineBusy;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: _onlineBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_outlined, size: 18),
            label: Text(AppStrings.t('summary_online_btn', context)),
            onPressed: busy ? null : _generateOnlineSummary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            icon: _isLoadingSummary
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.summarize_outlined, size: 18),
            label: Text(AppStrings.t('summary_local_btn', context)),
            onPressed: busy ? null : _generateSummary,
          ),
        ),
      ],
    );
  }

  // ============ Экспорт / копирование ============

  void _shareContent(BuildContext context) {
    final buffer = StringBuffer();
    buffer.writeln('=== ${widget.recording.title} ===');
    buffer.writeln('Дата: ${formatDateTime(widget.recording.dateTime ?? DateTime.now())}');
    buffer.writeln('Длительность: ${formatDuration(widget.recording.duration ?? Duration.zero)}');
    buffer.writeln();

    final r = _mode == 1 ? _onlineResult : _localResult;
    if (r != null) {
      buffer.writeln(r.formatted);
    } else if (widget.recording.summary != null) {
      buffer.writeln(widget.recording.summary);
    }

    if (widget.recording.transcript != null) {
      buffer.writeln();
      buffer.writeln('--- Полный текст ---');
      buffer.writeln(widget.recording.transcript);
    }

    Share.share(buffer.toString(), subject: widget.recording.title);
  }

  void _copyToClipboard(BuildContext context) {
    final buffer = StringBuffer();
    final r = _mode == 1 ? _onlineResult : _localResult;
    if (r != null) {
      buffer.writeln(r.formatted);
    } else if (widget.recording.summary != null) {
      buffer.writeln(widget.recording.summary);
    }
    if (widget.recording.transcript != null) {
      buffer.writeln();
      buffer.writeln(widget.recording.transcript);
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.t('text_copied', context))),
    );
  }
}
