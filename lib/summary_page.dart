import 'package:flutter/material.dart';
import 'audio_service.dart';
import 'services/enhanced_summary_service.dart';

class SummaryPage extends StatelessWidget {
  final Recording recording;

  const SummaryPage({super.key, required this.recording});

  @override
  Widget build(BuildContext context) {
    final rec = recording;
    final hasData = rec.transcription != null && rec.transcription!.isNotEmpty;

    // Используем EnhancedSummaryService для генерации саммари
    final SummaryResult summaryResult = hasData
        ? EnhancedSummaryService.generateSummary(recording.transcription!)
        : SummaryResult.empty();

    final summary = summaryResult.points;

    final decisions = recording.decisions != null && recording.decisions!.isNotEmpty
        ? recording.decisions!
        : [];

    final speakerStats = recording.speakerStats != null && recording.speakerStats!.isNotEmpty
        ? recording.speakerStats!
        : [];

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        title: Text(recording.title ?? 'Саммари'),
        backgroundColor: const Color(0xFF0A0A1A),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 18),
      ),
      body: !hasData
          ? const Center(
              child: Text(
                'Нет транскрипции для анализа',
                style: TextStyle(color: Colors.white54),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Заголовок с типом
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getTypeColor(summaryResult.type).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _getTypeColor(summaryResult.type).withOpacity(0.5),
                      ),
                    ),
                    child: Text(
                      _getTypeLabel(summaryResult.type),
                      style: TextStyle(
                        color: _getTypeColor(summaryResult.type),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Суть
                  _SectionTitle(icon: Icons.summarize, title: summaryResult.title),
                  const SizedBox(height: 8),
                  ...summary.map((s) => _BulletText(s)).toList(),
                  const SizedBox(height: 24),

                  // Решения (только для business)
                  if (summaryResult.type == TextType.business) ...[
                    _SectionTitle(icon: Icons.check_circle, title: 'Ключевые решения'),
                    const SizedBox(height: 8),
                    if (decisions.isEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.white38, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'В записи не найдено маркеров решений',
                                style: TextStyle(color: Colors.white38, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ...decisions.map((d) => _DecisionItem(d)).toList(),
                    const SizedBox(height: 24),
                  ],

                  // Говорящие
                  if (speakerStats.isNotEmpty) ...[
                    _SectionTitle(icon: Icons.people, title: 'Участники'),
                    const SizedBox(height: 8),
                    ...speakerStats.map((s) => _SpeakerCard(s)).toList(),
                  ],
                ],
              ),
            ),
    );
  }

  Color _getTypeColor(TextType type) {
    switch (type) {
      case TextType.narrative:
        return Colors.orange;
      case TextType.business:
        return Colors.green;
      case TextType.educational:
        return Colors.blue;
      case TextType.general:
        return Colors.purple;
    }
  }

  String _getTypeLabel(TextType type) {
    switch (type) {
      case TextType.narrative:
        return 'История / Рассказ';
      case TextType.business:
        return 'Совещание / Деловая встреча';
      case TextType.educational:
        return 'Лекция / Образование';
      case TextType.general:
        return 'Общая запись';
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.cyan, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _BulletText extends StatelessWidget {
  final String text;

  const _BulletText(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Colors.cyan, fontSize: 14)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _DecisionItem extends StatelessWidget {
  final String text;

  const _DecisionItem(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A5F),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check, color: Colors.green, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeakerCard extends StatelessWidget {
  final Map<String, dynamic> stat;

  const _SpeakerCard(this.stat);

  @override
  Widget build(BuildContext context) {
    final speaker = stat['speaker'] as String;
    final count = stat['utteranceCount'] as int;
    final words = stat['wordCount'] as int;
    final topWords = (stat['topWords'] as List<dynamic>?)
            ?.map((e) => '${e.key} (${e.value})')
            .join(', ') ??
        '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: speaker == 'A' ? const Color(0xFF1E3A5F) : const Color(0xFF1E4A3A),
                child: Text(
                  speaker,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$count фраз, $words слов',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          if (topWords.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Топ слов: $topWords',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
