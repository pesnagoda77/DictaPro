import 'dart:math';

/// Эвристический алгоритм разделения говорящих (Speaker Diarization)
/// Работает офлайн, без тяжёлых ML-моделей
/// 
/// Логика:
/// 1. Длинная пауза (>2с) = смена говорящего
/// 2. Резкое изменение pitch (высоты тона) = смена говорящего
/// 3. Резкое изменение громкости = возможная смена
/// 4. Подряд >5 строк от одного говорящего = принудительная проверка
class SpeakerDiarizationService {
  static const double PAUSE_SPEAKER_CHANGE = 2.0;     // сек — пауза между репликами
  static const double PITCH_CHANGE_THRESHOLD = 0.15;  // 15% изменение pitch
  static const double VOLUME_CHANGE_THRESHOLD = 0.20; // 20% изменение громкости
  static const int MAX_CONSECUTIVE_LINES = 5;         // макс строк подряд от одного

  /// Разделяет текст на диалог с разными говорящими
  static List<DialogueSegment> segmentSpeakers(
    List<TranscriptionChunk> chunks,
  ) {
    if (chunks.isEmpty) return [];

    List<DialogueSegment> segments = [];
    int currentSpeaker = 1;
    List<TranscriptionChunk> currentChunks = [chunks[0]];

    for (int i = 1; i < chunks.length; i++) {
      TranscriptionChunk prev = chunks[i - 1];
      TranscriptionChunk curr = chunks[i];

      bool shouldChange = _shouldChangeSpeaker(
        prev: prev,
        curr: curr,
        consecutiveLines: currentChunks.length,
      );

      if (shouldChange) {
        // Сохраняем текущий сегмент
        segments.add(DialogueSegment(
          speaker: 'Speaker $currentSpeaker',
          chunks: List.from(currentChunks),
          text: currentChunks.map((c) => c.text).join(' '),
        ));

        // Меняем говорящего (1 ↔ 2)
        currentSpeaker = currentSpeaker == 1 ? 2 : 1;
        currentChunks = [curr];
      } else {
        currentChunks.add(curr);
      }
    }

    // Сохраняем последний сегмент
    if (currentChunks.isNotEmpty) {
      segments.add(DialogueSegment(
        speaker: 'Speaker $currentSpeaker',
        chunks: List.from(currentChunks),
        text: currentChunks.map((c) => c.text).join(' '),
      ));
    }

    return segments;
  }

  /// Определяет, нужно ли менять говорящего
  static bool _shouldChangeSpeaker({
    required TranscriptionChunk prev,
    required TranscriptionChunk curr,
    required int consecutiveLines,
  }) {
    // 1. Длинная пауза = смена говорящего
    double pause = curr.startTime - prev.endTime;
    if (pause > PAUSE_SPEAKER_CHANGE) return true;

    // 2. Резкое изменение pitch (высоты тона)
    if (prev.pitch != null && curr.pitch != null) {
      double pitchDiff = (curr.pitch! - prev.pitch!).abs() / prev.pitch!;
      if (pitchDiff > PITCH_CHANGE_THRESHOLD) return true;
    }

    // 3. Резкое изменение громкости
    if (prev.volume != null && curr.volume != null) {
      double volumeDiff = (curr.volume! - prev.volume!).abs() / prev.volume!;
      if (volumeDiff > VOLUME_CHANGE_THRESHOLD) return true;
    }

    // 4. Принудительная смена после N строк подряд
    if (consecutiveLines >= MAX_CONSECUTIVE_LINES) {
      // Проверяем, есть ли признаки смены в последних 3 строках
      if (pause > PAUSE_SPEAKER_CHANGE * 0.7) return true;
    }

    return false;
  }

  /// Улучшенная версия: пытается определить пол говорящего
  static List<DialogueSegment> segmentWithGender(
    List<TranscriptionChunk> chunks,
  ) {
    var segments = segmentSpeakers(chunks);

    // Определяем пол по среднему pitch
    for (var segment in segments) {
      double avgPitch = segment.chunks
          .where((c) => c.pitch != null)
          .map((c) => c.pitch!)
          .fold(0.0, (a, b) => a + b) /
          segment.chunks.where((c) => c.pitch != null).length;

      if (avgPitch > 0) {
        // Женский голос обычно выше (200-300 Hz)
        // Мужской ниже (80-150 Hz)
        String gender = avgPitch > 180 ? 'Female' : 'Male';
        segment.speaker = '$gender ${segment.speaker}';
      }
    }

    return segments;
  }
}

/// Часть транскрипции (chunk)
class TranscriptionChunk {
  final String text;
  final double startTime;
  final double endTime;
  final double? pitch;    // высота тона (Hz), если доступно
  final double? volume;   // громкость (0-1), если доступно
  final double confidence;

  TranscriptionChunk({
    required this.text,
    required this.startTime,
    required this.endTime,
    this.pitch,
    this.volume,
    required this.confidence,
  });
}

/// Сегмент диалога
class DialogueSegment {
  String speaker;
  final List<TranscriptionChunk> chunks;
  final String text;

  DialogueSegment({
    required this.speaker,
    required this.chunks,
    required this.text,
  });

  /// Длительность сегмента
  double get duration => chunks.last.endTime - chunks.first.startTime;

  /// Средняя уверенность
  double get avgConfidence =>
      chunks.map((c) => c.confidence).reduce((a, b) => a + b) / chunks.length;
}

/// Пример использования:
/// ```dart
/// var chunks = [
///   TranscriptionChunk(text: 'Привет', startTime: 0.0, endTime: 0.5, pitch: 120, confidence: 0.9),
///   TranscriptionChunk(text: 'как дела', startTime: 0.6, endTime: 1.2, pitch: 125, confidence: 0.85),
///   // пауза 2.5 сек — смена говорящего
///   TranscriptionChunk(text: 'Нормально', startTime: 3.7, endTime: 4.5, pitch: 220, confidence: 0.9),
/// ];
/// 
/// var segments = SpeakerDiarizationService.segmentSpeakers(chunks);
/// // segments[0].speaker = 'Speaker 1' (мужской, низкий pitch)
/// // segments[1].speaker = 'Speaker 2' (женский, высокий pitch)
/// ```
