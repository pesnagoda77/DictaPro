import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dictapro/services/audio_fragment_service.dart';

void main() {
  test('parseWav читает fmt и data из сгенерированного заголовка', () {
    final header = AudioFragmentService.wavHeader(
        32000, 16000, 1, 16); // 1 секунда PCM 16 кГц моно
    final bytes = Uint8List(header.length + 32000)
      ..setRange(0, header.length, header);
    final info = AudioFragmentService.parseWav(bytes);
    expect(info, isNotNull);
    expect(info!.sampleRate, 16000);
    expect(info.channels, 1);
    expect(info.bitsPerSample, 16);
    expect(info.dataOffset, 44);
    expect(info.dataLength, 32000);
    expect(info.durationSec, closeTo(1.0, 0.001));
  });

  test('parseWav не падает на мусоре', () {
    expect(AudioFragmentService.parseWav(Uint8List(10)), isNull);
    expect(AudioFragmentService.parseWav(Uint8List(100)), isNull);
  });
}
