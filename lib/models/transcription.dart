// Общие модели результата транскрибации (task 019).
// Раньше дублировались: lib/transcription_service.dart (VOSK, с таймкодами)
// и lib/audio_service.dart (без). Теперь — одно место.
// fromMap переживает старые записи Hive без startTime/endTime.

class DialogueSegment {
  String speaker;
  String text;
  double startTime;
  double endTime;

  DialogueSegment({
    required this.speaker,
    required this.text,
    this.startTime = 0,
    this.endTime = 0,
  });

  Map<String, dynamic> toMap() => {
        'speaker': speaker,
        'text': text,
        'startTime': startTime,
        'endTime': endTime,
      };

  factory DialogueSegment.fromMap(Map<String, dynamic> map) => DialogueSegment(
        speaker: map['speaker'] as String? ?? 'A',
        text: map['text'] as String? ?? '',
        startTime: (map['startTime'] as num?)?.toDouble() ?? 0,
        endTime: (map['endTime'] as num?)?.toDouble() ?? 0,
      );
}

class TranscriptionResult {
  final String fullText;
  final List<DialogueSegment> segments;

  TranscriptionResult({
    required this.fullText,
    required this.segments,
  });
}
