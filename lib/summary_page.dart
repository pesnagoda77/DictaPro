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
import 'widgets/dicta_ui.dart';
import 'widgets/operation_progress.dart';

/// SummaryPage: экран «Итоги» (task 068).
///
/// Вид — по макету V3, экран 11: переключатель «Локально / Онлайн»,
/// блоки «О чём договорились / Задачи / Цифры и даты», примечание про
/// ИИ-часы и кэш, кнопка «Обновить». Логика (локальный расчёт в изоляте,
/// онлайн-сервер, кэш, списание ИИ-часов) сохранена без изменений.
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
  SummaryResult? _summaryResult;
  bool _isLoadingSummary = false;
  bool _localError = false;

  // Task 059: онлайн-итоги и счётчик ИИ-часов.
  bool _onlineBusy = false;
  bool _onlineWasUsed = false;
  bool _onlineMode = false;
  bool _onlineNoHours = false;
  bool _onlineError = false;
  SummaryResult? _onlineResult;
  String _hoursLabel = '';

  // Task 034: этап операции для индикатора с секундомером.
  final ValueNotifier<String> _stage = ValueNotifier('Готовим текст…');

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

  bool get _hasTranscript =>
      widget.recording.transcript != null &&
      widget.recording.transcript!.isNotEmpty;

  // Task 034: саммари считается в изоляте — главный поток свободен,
  // счётчик тикает, пользователь может уйти с экрана и вернуться.
  Future<void> _generateSummary() async {
    if (widget.recording.transcript == null ||
        widget.recording.transcript!.isEmpty) return;

    setState(() {
      _isLoadingSummary = true;
      _localError = false;
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
        _summaryResult = summary;
        _isLoadingSummary = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingSummary = false;
        _localError = true;
      });
    }
  }

  Future<void> _refreshHoursLabel() async {
    final label = await AiHoursService.instance.balanceLabel();
    if (mounted) setState(() => _hoursLabel = label);
  }

  /// Task 059: онлайн-итоги. Gate для бесплатных: без подписки и без
  /// пакетов кнопка неактивна, серверная авторизация — второй рубеж
  /// (проверка «бесплатный не может отправить ничего» — перехватом).
  Future<void> _generateOnlineSummary() async {
    final transcript = widget.recording.transcript;
    if (transcript == null || transcript.isEmpty || _onlineBusy) return;
    final audioMs = widget.recording.duration?.inMilliseconds ?? 0;

    setState(() {
      _onlineNoHours = false;
      _onlineError = false;
    });

    if (!await AiHoursService.instance.canSpend(audioMs)) {
      if (mounted) setState(() => _onlineNoHours = true);
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

    setState(() => _onlineBusy = true);
    _stage.value = AppStrings.t('online_summary_stage', context);
    try {
      final res = await OnlineSummaryService.instance.summarize(
        fileId: widget.recording.filePath ?? widget.recording.title,
        text: transcript,
        audioMs: audioMs,
        lang: Localizations.localeOf(context).languageCode,
      );
      if (!mounted) return;
      if (res == null) {
        setState(() => _onlineError = true);
        return;
      }
      setState(() {
        _onlineWasUsed = true;
        _onlineResult = SummaryResult(
          title: AppStrings.t('online_summary_title', context),
          type: TextType.general,
          points: res.text.split('\n').where((e) => e.trim().isNotEmpty).toList(),
          fullText: transcript,
        );
      });
      await _refreshHoursLabel();
      _showSnack(res.fromCache
          ? AppStrings.t('online_summary_from_cache', context)
          : AppStrings.tf('online_summary_spent', context,
              {'h': _fmtHours(res.aiHoursSpent)}));
      await widget.onSave?.call(res.text);
    } finally {
      if (mounted) setState(() => _onlineBusy = false);
    }
  }

  String _fmtHours(double h) => h.toStringAsFixed(1);

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final tk = DictaTokens.of(context);
    return DictaBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          titleSpacing: 16,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.recording.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              Text(
                AppStrings.t('summary_subtitle', context),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: tk.mint,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: AppStrings.t('share_title', context),
              onPressed: () => _shareContent(context),
            ),
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: AppStrings.t('export_copy', context),
              onPressed: () => _copyToClipboard(context),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _modeToggle(context),
            const SizedBox(height: 10),
            _metaLine(context),
            const SizedBox(height: 12),
            ..._content(context),
            if (_hasTranscript) _fullTextCard(context),
            _notePlate(context),
            _hoursLine(context),
            if (_hasTranscript) ...[
              const SizedBox(height: 2),
              _cta(context),
            ],
          ],
        ),
      ),
    );
  }

  // ── Переключатель «Локально / Онлайн» (макет, экран 11) ─────────────

  Widget _modeToggle(BuildContext context) {
    final tk = DictaTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: tk.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tk.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: _modeSegment(
              context,
              title: AppStrings.t('summary_mode_local', context),
              sub: AppStrings.t('summary_mode_local_sub', context),
              active: !_onlineMode,
              onTap: () => setState(() => _onlineMode = false),
            ),
          ),
          Expanded(
            child: _modeSegment(
              context,
              title: AppStrings.t('summary_mode_online', context),
              sub: AppStrings.t('summary_mode_online_sub', context),
              active: _onlineMode,
              onTap: () => setState(() => _onlineMode = true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeSegment(
    BuildContext context, {
    required String title,
    required String sub,
    required bool active,
    required VoidCallback onTap,
  }) {
    final tk = DictaTokens.of(context);
    final onAccent = Theme.of(context).colorScheme.onPrimary;
    final color = active ? onAccent : tk.ink3;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: active ? tk.mint : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            Text(
              sub,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: active ? color.withValues(alpha: 0.85) : tk.ink3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Мета записи (моно): длительность · дата ─────────────────────────

  Widget _metaLine(BuildContext context) {
    final tk = DictaTokens.of(context);
    final parts = <String>[];
    final d = widget.recording.duration;
    final dt = widget.recording.dateTime;
    if (d != null) parts.add(formatDuration(d));
    if (dt != null) parts.add(formatDateTime(dt));
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join(' · '),
      style: tk.mono(10.5, FontWeight.w500, tk.ink3),
    );
  }

  // ── Содержимое по состоянию ─────────────────────────────────────────

  List<Widget> _content(BuildContext context) {
    final tk = DictaTokens.of(context);
    if (!_hasTranscript) {
      return [
        _statePlate(
          context,
          icon: Icons.article_outlined,
          text: AppStrings.t('no_transcript', context),
        ),
      ];
    }

    if (_onlineMode) {
      if (_onlineBusy) return [_loadingPlate(context)];
      if (_onlineNoHours) {
        return [
          _statePlate(
            context,
            icon: Icons.hourglass_empty,
            text: AppStrings.t('online_summary_no_hours', context),
            accent: tk.gold,
          ),
        ];
      }
      if (_onlineError) {
        return [
          _statePlate(
            context,
            icon: Icons.error_outline,
            text: AppStrings.t('online_summary_failed', context),
            accent: tk.red,
            onRetry: _generateOnlineSummary,
          ),
        ];
      }
      final online = _onlineResult;
      if (online != null) {
        final split = _splitOnline(online);
        return _blocks(context, split.deal, split.tasks, split.figures);
      }
      return [
        _statePlate(
          context,
          icon: Icons.cloud_outlined,
          text: AppStrings.t('online_summary_not_yet', context),
        ),
      ];
    }

    if (_isLoadingSummary) return [_loadingPlate(context)];
    if (_localError) {
      return [
        _statePlate(
          context,
          icon: Icons.error_outline,
          text: AppStrings.t('summary_failed_snack', context),
          accent: tk.red,
          onRetry: _generateSummary,
        ),
      ];
    }
    final local = _summaryResult;
    if (local != null) {
      final split = _splitLocal(local);
      return [
        _typePill(context, local),
        ..._blocks(context, split.deal, split.tasks, split.figures),
      ];
    }
    final saved = widget.recording.summary;
    if (saved != null &&
        saved.isNotEmpty &&
        saved != AppStrings.t('no_summary_yet', context)) {
      return [
        DictaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _blockTitle(context, AppStrings.t('summary_card_title', context)),
              Text(
                saved,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: tk.ink2,
                ),
              ),
            ],
          ),
        ),
      ];
    }
    return [
      _statePlate(
        context,
        icon: Icons.auto_awesome_outlined,
        text: AppStrings.t('summary_press_button', context),
      ),
    ];
  }

  // ── Блоки итогов ────────────────────────────────────────────────────

  List<Widget> _blocks(
    BuildContext context,
    List<String> deal,
    List<String> tasks,
    List<String> figures,
  ) {
    final out = <Widget>[];
    if (deal.isNotEmpty) {
      out.add(
        DictaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _blockTitle(context, AppStrings.t('summary_block_deal', context)),
              for (final s in deal) _dealRow(context, s),
            ],
          ),
        ),
      );
    }
    if (tasks.isNotEmpty) {
      out.add(
        DictaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _blockTitle(context, AppStrings.t('summary_block_tasks', context)),
              for (final s in tasks) _taskRow(context, s),
            ],
          ),
        ),
      );
    }
    if (figures.isNotEmpty) {
      out.add(
        DictaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _blockTitle(context, AppStrings.t('summary_block_figures', context)),
              for (final s in figures) _dealRow(context, s),
            ],
          ),
        ),
      );
    }
    return out;
  }

  Widget _blockTitle(BuildContext context, String text) {
    final tk = DictaTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: tk.mint,
        ),
      ),
    );
  }

  Widget _dealRow(BuildContext context, String text) {
    final tk = DictaTokens.of(context);
    final span = _leadSpan(context, text);
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text.rich(
        span,
        style: TextStyle(fontSize: 12.5, height: 1.5, color: tk.ink2),
      ),
    );
  }

  /// Лёд-слово до двоеточия — жирным (как `<b>` в макете).
  TextSpan _leadSpan(BuildContext context, String text) {
    final tk = DictaTokens.of(context);
    final idx = text.indexOf(':');
    if (idx > 0 && idx < 40) {
      return TextSpan(
        style: TextStyle(fontSize: 12.5, height: 1.5, color: tk.ink2),
        children: [
          TextSpan(
            text: text.substring(0, idx + 1),
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: tk.ink,
            ),
          ),
          TextSpan(text: text.substring(idx + 1)),
        ],
      );
    }
    return TextSpan(text: text);
  }

  Widget _taskRow(BuildContext context, String text) {
    final tk = DictaTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 13,
            height: 13,
            margin: const EdgeInsets.only(top: 2.5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: tk.mint, width: 1.5),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, height: 1.5, color: tk.ink2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typePill(BuildContext context, SummaryResult r) {
    final tk = DictaTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: tk.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_getTypeIcon(r.type), size: 13, color: tk.ink2),
                const SizedBox(width: 5),
                Text(
                  r.typeLabel,
                  style: TextStyle(fontSize: 10.5, color: tk.ink2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Плашки состояний ────────────────────────────────────────────────

  Widget _loadingPlate(BuildContext context) {
    return DictaCard(
      padding: const EdgeInsets.all(14),
      child: Center(child: OperationProgressView(stage: _stage)),
    );
  }

  Widget _statePlate(
    BuildContext context, {
    required IconData icon,
    required String text,
    Color? accent,
    VoidCallback? onRetry,
  }) {
    final tk = DictaTokens.of(context);
    final tone = accent ?? tk.ink2;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tk.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent == null ? tk.line : accent.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: tone),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: tk.ink2,
                  ),
                ),
              ),
            ],
          ),
          if (onRetry != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 28),
              child: TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: onRetry,
                child: Text(AppStrings.t('retry', context)),
              ),
            ),
        ],
      ),
    );
  }

  /// Примечание-плашка (пунктирная рамка, как `.note-r` в макете).
  Widget _notePlate(BuildContext context) {
    final tk = DictaTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: tk.mint.withValues(alpha: 0.3),
          radius: 14,
        ),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Text(
            AppStrings.t('summary_note', context),
            style: TextStyle(fontSize: 11.5, height: 1.5, color: tk.ink2),
          ),
        ),
      ),
    );
  }

  Widget _hoursLine(BuildContext context) {
    if (_hoursLabel.isEmpty) return const SizedBox.shrink();
    final tk = DictaTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _hoursLabel,
              style: tk.mono(10.5, FontWeight.w500, tk.ink3),
            ),
          ),
          if (_onlineWasUsed)
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: _refreshHoursLabel,
              child: Text(AppStrings.t('online_summary_refresh', context)),
            ),
        ],
      ),
    );
  }

  // ── Полный текст записи ─────────────────────────────────────────────

  Widget _fullTextCard(BuildContext context) {
    final tk = DictaTokens.of(context);
    return DictaCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _showFullText = !_showFullText),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Text(
                    AppStrings.t('summary_full_text', context),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _showFullText ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: tk.ink2,
                  ),
                ],
              ),
            ),
          ),
          if (_showFullText)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(
                widget.recording.transcript!,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: tk.ink2,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Кнопка «Обновить» ───────────────────────────────────────────────

  Widget _cta(BuildContext context) {
    final busy = _isLoadingSummary || _onlineBusy;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: busy
            ? null
            : (_onlineMode ? _generateOnlineSummary : _generateSummary),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              )
            else
              const Icon(Icons.refresh, size: 18),
            const SizedBox(width: 8),
            Text(AppStrings.t('online_summary_refresh', context)),
          ],
        ),
      ),
    );
  }

  // ── Разбор итогов на блоки ──────────────────────────────────────────

  static final RegExp _markerRe =
      RegExp(r'^\s*(□|•|💡|📅|\?|Q:)\s*(.*)$');

  ({List<String> deal, List<String> tasks, List<String> figures}) _splitLocal(
    SummaryResult r,
  ) {
    final deal = <String>[];
    final tasks = <String>[];
    final figures = <String>[];
    final seen = <String>[];

    bool dup(String t) {
      final k = t.toLowerCase();
      for (final e in seen) {
        if (e.contains(k) || k.contains(e)) return true;
      }
      return false;
    }

    void add(List<String> bucket, String raw) {
      final t = raw.trim();
      if (t.isEmpty || dup(t)) return;
      seen.add(t.toLowerCase());
      bucket.add(t);
    }

    String header = '';
    for (final raw in r.points) {
      final t = raw.trim();
      final m = _markerRe.firstMatch(raw);
      if (m == null) {
        if (t.endsWith(':')) {
          header = t.toLowerCase();
        } else {
          add(deal, t);
        }
        continue;
      }
      final marker = m.group(1);
      final text = m.group(2) ?? '';
      if (marker == '□') {
        add(tasks, text);
      } else if (marker == '📅' || _figureHeader(header)) {
        add(figures, text);
      } else {
        add(deal, text);
      }
    }
    for (final a in r.actionItems) {
      add(tasks, a);
    }
    for (final d in r.deadlines) {
      add(figures, d);
    }
    for (final a in r.amounts) {
      add(figures, a);
    }
    for (final c in r.contacts) {
      add(figures, c);
    }
    for (final d in r.dates) {
      add(figures, d);
    }
    return (deal: deal, tasks: tasks, figures: figures);
  }

  bool _figureHeader(String h) =>
      h.contains('срок') ||
      h.contains('финанс') ||
      h.contains('сумм') ||
      h.contains('контакт') ||
      h.contains('цифр') ||
      h.contains('дат');

  ({List<String> deal, List<String> tasks, List<String> figures}) _splitOnline(
    SummaryResult r,
  ) {
    final deal = <String>[];
    final tasks = <String>[];
    final figures = <String>[];
    final seen = <String>[];
    var bucket = deal;

    bool dup(String t) {
      final k = t.toLowerCase();
      for (final e in seen) {
        if (e.contains(k) || k.contains(e)) return true;
      }
      return false;
    }

    void add(String raw) {
      var t = raw.trim().replaceAll('**', '');
      t = t.replaceFirst(RegExp(r'^[-–—•*]\s+'), '');
      t = t.replaceFirst(RegExp(r'^\d+[.)]\s+'), '');
      t = t.trim();
      if (t.isEmpty || dup(t)) return;
      seen.add(t.toLowerCase());
      bucket.add(t);
    }

    for (final raw in r.points) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      final clean = t.replaceAll(RegExp(r'[#*]'), '').trim();
      if (clean.isEmpty) continue;
      final low = clean.toLowerCase();
      final fig = low.contains('цифр') ||
          low.contains('дат') ||
          low.contains('срок') ||
          low.contains('numbers') ||
          low.contains('dates') ||
          low.contains('zahlen') ||
          low.contains('numeri');
      final task = low.contains('задач') ||
          low.contains('что делать') ||
          low.contains('tasks') ||
          low.contains('aufgaben') ||
          low.contains('attività') ||
          low.contains('attivita');
      final dealHead = low.contains('договор') ||
          low.contains('о чём') ||
          low.contains('о чем') ||
          low.contains('agreed') ||
          low.contains('vereinbart') ||
          low.contains('concordato');
      final looksHead = t.endsWith(':') ||
          raw.trimLeft().startsWith('#') ||
          (clean == clean.toUpperCase() && clean.length <= 48);
      if (looksHead && (fig || task || dealHead)) {
        if (dealHead) {
          bucket = deal;
        } else if (task) {
          bucket = tasks;
        } else {
          bucket = figures;
        }
        continue;
      }
      add(raw);
    }
    return (deal: deal, tasks: tasks, figures: figures);
  }

  IconData _getTypeIcon(TextType type) {
    switch (type) {
      case TextType.business:
        return Icons.business;
      case TextType.educational:
        return Icons.school;
      case TextType.interview:
        return Icons.record_voice_over;
      case TextType.personal:
        return Icons.person;
      case TextType.narrative:
        return Icons.book;
      case TextType.general:
        return Icons.summarize;
    }
  }

  // ── Экспорт / копирование (логика без изменений) ────────────────────

  void _shareContent(BuildContext context) {
    final buffer = StringBuffer();
    buffer.writeln('=== ${widget.recording.title} ===');
    buffer.writeln('Дата: ${formatDateTime(widget.recording.dateTime ?? DateTime.now())}');
    buffer.writeln('Длительность: ${formatDuration(widget.recording.duration ?? Duration.zero)}');
    buffer.writeln();

    if (_summaryResult != null) {
      buffer.writeln(_summaryResult!.formatted);
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
    if (_summaryResult != null) {
      buffer.writeln(_summaryResult!.formatted);
    } else if (widget.recording.summary != null) {
      buffer.writeln(widget.recording.summary);
    }
    if (widget.recording.transcript != null) {
      buffer.writeln();
      buffer.writeln(widget.recording.transcript);
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.t('copied_to_clipboard', context))),
    );
  }
}

/// Пунктирная рамка для примечания-плашки (аналог dashed-бордера в макете).
class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({
    required this.color,
    this.radius = 14,
    this.dash = 5,
    this.gap = 4,
    this.strokeWidth = 1,
  });

  final Color color;
  final double radius;
  final double dash;
  final double gap;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final next = dist + dash < metric.length ? dist + dash : metric.length;
        canvas.drawPath(metric.extractPath(dist, next), paint);
        dist = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.dash != dash ||
      oldDelegate.gap != gap ||
      oldDelegate.strokeWidth != strokeWidth;
}
