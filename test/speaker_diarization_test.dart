import 'package:flutter_test/flutter_test.dart';
import 'package:dictapro/services/speaker_diarization.dart';

void main() {
  group('SpeakerDiarizationService', () {
    test('changes speaker on long pause', () {
      var chunks = [
        TranscriptionChunk(
          text: 'Привет',
          startTime: 0.0,
          endTime: 0.5,
          pitch: 120,
          confidence: 0.9,
        ),
        // Пауза 2.5 сек — смена
        TranscriptionChunk(
          text: 'Нормально',
          startTime: 3.0,
          endTime: 3.5,
          pitch: 220,
          confidence: 0.9,
        ),
      ];

      var segments = SpeakerDiarizationService.segmentSpeakers(chunks);

      expect(segments.length, 2);
      expect(segments[0].speaker, 'Speaker 1');
      expect(segments[1].speaker, 'Speaker 2');
    });

    test('changes speaker on pitch change', () {
      var chunks = [
        TranscriptionChunk(
          text: 'Привет',
          startTime: 0.0,
          endTime: 0.5,
          pitch: 120,
          confidence: 0.9,
        ),
        // pitch изменился на 50% — смена
        TranscriptionChunk(
          text: 'Привет',
          startTime: 0.6,
          endTime: 1.1,
          pitch: 220,
          confidence: 0.9,
        ),
      ];

      var segments = SpeakerDiarizationService.segmentSpeakers(chunks);

      expect(segments.length, 2);
      expect(segments[0].speaker, 'Speaker 1');
      expect(segments[1].speaker, 'Speaker 2');
    });

    test('keeps same speaker on short pause', () {
      var chunks = [
        TranscriptionChunk(
          text: 'Привет',
          startTime: 0.0,
          endTime: 0.5,
          pitch: 120,
          confidence: 0.9,
        ),
        // Пауза 0.5 сек — тот же говорящий
        TranscriptionChunk(
          text: 'как дела',
          startTime: 1.0,
          endTime: 1.5,
          pitch: 125,
          confidence: 0.9,
        ),
      ];

      var segments = SpeakerDiarizationService.segmentSpeakers(chunks);

      expect(segments.length, 1);
      expect(segments[0].speaker, 'Speaker 1');
    });

    test('forces change after 5 consecutive lines', () {
      var chunks = List.generate(6, (i) => TranscriptionChunk(
        text: 'Слово $i',
        startTime: i * 1.0,
        endTime: i * 1.0 + 0.5,
        pitch: 120,
        confidence: 0.9,
      ));

      var segments = SpeakerDiarizationService.segmentSpeakers(chunks);

      expect(segments.length, 2);
    });

    test('detects gender by pitch', () {
      var chunks = [
        TranscriptionChunk(
          text: 'Привет',
          startTime: 0.0,
          endTime: 0.5,
          pitch: 120, // низкий — мужской
          confidence: 0.9,
        ),
        TranscriptionChunk(
          text: 'Привет',
          startTime: 2.5,
          endTime: 3.0,
          pitch: 250, // высокий — женский
          confidence: 0.9,
        ),
      ];

      var segments = SpeakerDiarizationService.segmentWithGender(chunks);

      expect(segments[0].speaker, contains('Male'));
      expect(segments[1].speaker, contains('Female'));
    });
  });
}
