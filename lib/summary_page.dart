import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'services/enhanced_summary_service.dart';
import 'models/recording_details_model.dart';
import 'utils.dart';

/// SummaryPage: Displays detailed summary of a recording with transcription.
class SummaryPage extends StatefulWidget {
  final RecordingDetailsModel recording;

  const SummaryPage({
    super.key,
    required this.recording,
  });

  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage> {
  bool _showFullText = false;
  SummaryResult? _summaryResult;
  bool _isLoadingSummary = false;

  @override
  void initState() {
    super.initState();
    if (widget.recording.summary != null && 
        widget.recording.summary!.isNotEmpty &&
        widget.recording.summary != 'Нет доступного резюме') {
      _generateSummary();
    }
  }

  void _generateSummary() {
    if (widget.recording.transcript == null || 
        widget.recording.transcript!.isEmpty) return;

    setState(() => _isLoadingSummary = true);

    Future.delayed(const Duration(milliseconds: 100), () {
      final summary = EnhancedSummaryService.generateSummary(
        widget.recording.transcript!,
      );
      setState(() {
        _summaryResult = summary;
        _isLoadingSummary = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Саммари'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _shareContent(context),
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () => _copyToClipboard(context),
          ),
        ],
      ),
      body: _buildSummaryContent(widget.recording, context),
    );
  }

  Widget _buildSummaryContent(
    RecordingDetailsModel recording,
    BuildContext context,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Recording Details Card
          _buildRecordingDetailsCard(recording, context),
          const SizedBox(height: 16),

          // Summary Type Badge
          if (_summaryResult != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _getTypeColor(_summaryResult!.type).withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _summaryResult!.typeLabel,
                style: TextStyle(
                  color: _getTypeColor(_summaryResult!.type),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Summary Content
          _buildSummaryCard(recording, context),
          const SizedBox(height: 16),

          // Full Text Toggle
          if (recording.transcript != null && 
              recording.transcript!.isNotEmpty) ...[
            _buildFullTextSection(recording, context),
          ],
        ],
      ),
    );
  }

  Color _getTypeColor(TextType type) {
    switch (type) {
      case TextType.business: return Colors.green;
      case TextType.educational: return Colors.blue;
      case TextType.interview: return Colors.orange;
      case TextType.personal: return Colors.purple;
      case TextType.narrative: return Colors.amber;
      case TextType.general: return Colors.grey;
    }
  }

  Widget _buildSummaryCard(RecordingDetailsModel recording, BuildContext context) {
    if (_isLoadingSummary) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_summaryResult == null) {
      // Fallback to original summary
      if (recording.summary != null && 
          recording.summary!.isNotEmpty &&
          recording.summary != 'Нет доступного резюме') {
        return _buildInfoCard(
          context,
          title: 'Краткое содержание',
          content: recording.summary!,
        );
      }
      return _buildInfoCard(
        context,
        title: 'Саммари',
        content: 'Нажмите кнопку ниже для генерации саммари',
      );
    }

    // Enhanced summary display
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getTypeIcon(_summaryResult!.type),
                  color: _getTypeColor(_summaryResult!.type),
                ),
                const SizedBox(width: 8),
                Text(
                  _summaryResult!.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),

            // Summary points
            ..._summaryResult!.points.map((point) => _buildSummaryPoint(point)),

            // Action items (if any)
            if (_summaryResult!.actionItems.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(height: 16),
              Text(
                'Экшн-айтемы:',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 8),
              ..._summaryResult!.actionItems.map((item) => _buildActionItem(item)),
            ],

            // Contacts (if any)
            if (_summaryResult!.contacts.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(height: 16),
              Text(
                'Контакты:',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 8),
              ..._summaryResult!.contacts.map((c) => _buildContactChip(c)),
            ],

            // Deadlines (if any)
            if (_summaryResult!.deadlines.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(height: 16),
              Text(
                'Сроки:',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(height: 8),
              ..._summaryResult!.deadlines.map((d) => _buildDeadlineChip(d)),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getTypeIcon(TextType type) {
    switch (type) {
      case TextType.business: return Icons.business;
      case TextType.educational: return Icons.school;
      case TextType.interview: return Icons.record_voice_over;
      case TextType.personal: return Icons.person;
      case TextType.narrative: return Icons.book;
      case TextType.general: return Icons.summarize;
    }
  }

  Widget _buildSummaryPoint(String point) {
    // Check if it's a section header
    if (point.endsWith(':') || 
        (!point.startsWith('  ') && !point.startsWith('•') && 
         !point.startsWith('□') && !point.startsWith('💡') && 
         !point.startsWith('📅') && !point.startsWith('?'))) {
      return Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(
          point,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      );
    }

    // Check for special markers
    if (point.startsWith('  □')) {
      return _buildCheckboxItem(point.substring(4));
    }
    if (point.startsWith('  💡')) {
      return _buildIdeaItem(point.substring(4));
    }
    if (point.startsWith('  📅')) {
      return _buildDateItem(point.substring(4));
    }
    if (point.startsWith('  ?')) {
      return _buildQuestionItem(point.substring(4));
    }
    if (point.startsWith('  Q:')) {
      return _buildQuestionItem(point.substring(4));
    }
    if (point.startsWith('  •')) {
      return _buildBulletItem(point.substring(4));
    }

    return _buildBulletItem(point);
  }

  Widget _buildBulletItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 16)),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckboxItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_box_outline_blank, size: 18, color: Colors.red),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdeaItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline, size: 18, color: Colors.amber),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.amber,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.event, size: 18, color: Colors.blue),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.blue,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.help_outline, size: 18, color: Colors.purple),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.purple,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionItem(String text) {
    return _buildCheckboxItem(text);
  }

  Widget _buildContactChip(String text) {
    return Chip(
      avatar: const Icon(Icons.contact_phone, size: 16),
      label: Text(text),
      backgroundColor: Colors.blue.withOpacity(0.1),
    );
  }

  Widget _buildDeadlineChip(String text) {
    return Chip(
      avatar: const Icon(Icons.timer, size: 16),
      label: Text(text),
      backgroundColor: Colors.orange.withOpacity(0.1),
    );
  }

  Widget _buildFullTextSection(RecordingDetailsModel recording, BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Полный текст',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _showFullText ? Icons.expand_less : Icons.expand_more,
                  ),
                  onPressed: () => setState(() => _showFullText = !_showFullText),
                ),
              ],
            ),
            if (_showFullText) ...[
              const Divider(height: 16),
              Text(
                recording.transcript!,
                style: TextStyle(
                  fontFamily: 'RobotoMono',
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ... other existing methods remain unchanged ...

  Widget _buildRecordingDetailsCard(RecordingDetailsModel recording, BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              recording.title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  formatDuration(recording.duration ?? Duration.zero),
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(width: 16),
                Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  formatDateTime(recording.dateTime ?? DateTime.now()),
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, {
    required String title,
    required String content,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(height: 16),
            Text(content),
          ],
        ),
      ),
    );
  }

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
      const SnackBar(content: Text('Скопировано в буфер обмена')),
    );
  }
}
