// Task 111: экспорт фрагмента аудио по выделенным строкам расшифровки.
//
// Идея (Славан): выделить несколько последовательных строк в расшифровке →
// получить соответствующий им кусок аудио отдельным файлом, которым можно
// поделиться («фрагмент 12-04–14-37.wav»).
//
// Реализация потоковая: файл записи не грузится в память целиком. Читаем
// заголовок WAV (RIFF-чанки), находим data, считаем байтовые границы по
// таймкодам и копируем нужный диапазон кусками по 1 МБ в новый WAV
// (тот же формат PCM — перекодирование не требуется, потери качества нет).
import 'dart:io';
import 'dart:typed_data';

import '../audio_service.dart';

/// Метаданные WAV-файла, нужные для байтовой резки.
class WavInfo {
  final int sampleRate;
  final int channels;
  final int bitsPerSample;

  /// Смещение первого байта PCM-данных от начала файла.
  final int dataOffset;

  /// Длина PCM-данных в байтах.
  final int dataLength;

  const WavInfo({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataLength,
  });

  /// Байт в секунду: sampleRate * channels * (bits / 8).
  double get byteRate => sampleRate * channels * (bitsPerSample ~/ 8).toDouble();

  /// Длительность файла в секундах.
  double get durationSec => byteRate > 0 ? dataLength / byteRate : 0;
}

class AudioFragmentService {
  /// Отступ с обеих сторон, чтобы не обрезать начало/конец слова.
  static const int paddingMs = 150;

  /// Запасной размер, если у старой записи нет таймкодов (end <= start).
  static const double fallbackSec = 15;

  /// Вырезает фрагмент [startSec]…[endSec] из записи [storedPath]
  /// и сохраняет его в папку записей. Возвращает путь к файлу или null.
  static Future<String?> exportFragment({
    required String storedPath,
    required double startSec,
    required double endSec,
  }) async {
    final resolved = await AudioService.resolveFilePath(storedPath);
    final src = File(resolved);
    if (!await src.exists()) return null;

    final raf = await src.open();
    try {
      // Заголовок WAV обычно 44 байта, но перед data может быть LIST/INFO —
      // читаем с запасом и идём по чанкам.
      final head = await raf.read(65536);
      final info = parseWav(head);
      if (info == null) return null;

      final pad = paddingMs / 1000.0;
      var from = (startSec - pad).clamp(0.0, info.durationSec);
      var to = (endSec + pad).clamp(0.0, info.durationSec);

      if (to <= from) {
        // Старые записи без endTime: берём разумный кусок от начала строки.
        from = startSec.clamp(0.0, info.durationSec);
        to = (from + fallbackSec).clamp(0.0, info.durationSec);
      }
      if (to <= from) return null;

      final startByte = info.dataOffset + (from * info.byteRate).round();
      var endByte = info.dataOffset + (to * info.byteRate).round();
      final dataEnd = info.dataOffset + info.dataLength;
      if (endByte > dataEnd) endByte = dataEnd;
      // Выравниваем по кадру (block align), чтобы не порвать сэмпл.
      final frame = info.channels * (info.bitsPerSample ~/ 8);
      if (frame > 1) {
        endByte = startByte + ((endByte - startByte) ~/ frame) * frame;
      }
      if (endByte <= startByte) return null;

      final dir = await AudioService.recordingsDir();
      final name = 'фрагмент ${_fmt(from)}–${_fmt(to)}.wav';
      final outPath = '${dir.path}/$name';

      final sink = File(outPath).openWrite();
      try {
        sink.add(wavHeader(endByte - startByte, info.sampleRate, info.channels,
            info.bitsPerSample));

        const chunkSize = 1 << 20; // 1 МБ
        var pos = startByte;
        await raf.setPosition(pos);
        while (pos < endByte) {
          final want = (endByte - pos) > chunkSize ? chunkSize : (endByte - pos);
          final buf = await raf.read(want);
          if (buf.isEmpty) break;
          sink.add(buf);
          pos += buf.length;
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      return outPath;
    } finally {
      await raf.close();
    }
  }

  /// Разбирает RIFF/WAVE: находит fmt и data.
  static WavInfo? parseWav(Uint8List bytes) {
    if (bytes.length < 44) return null;
    if (String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF') return null;
    if (String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') return null;

    var sampleRate = 0;
    var channels = 0;
    var bits = 0;
    var dataOffset = -1;
    var dataLength = 0;

    var pos = 12;
    while (pos + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final size = bytes[pos + 4] |
          (bytes[pos + 5] << 8) |
          (bytes[pos + 6] << 16) |
          (bytes[pos + 7] << 24);
      final body = pos + 8;
      if (id == 'fmt ' && body + 16 <= bytes.length) {
        channels = bytes[body + 2] | (bytes[body + 3] << 8);
        sampleRate = bytes[body + 4] |
            (bytes[body + 5] << 8) |
            (bytes[body + 6] << 16) |
            (bytes[body + 7] << 24);
        bits = bytes[body + 14] | (bytes[body + 15] << 8);
      } else if (id == 'data') {
        dataOffset = body;
        dataLength = size;
        break;
      }
      pos = body + size + (size.isOdd ? 1 : 0);
    }

    if (dataOffset < 0 || sampleRate <= 0 || channels <= 0 || bits <= 0) {
      return null;
    }
    // data может быть длиннее, чем реально есть в файле (обрезанная запись).
    if (dataOffset + dataLength > bytes.length) {
      dataLength = bytes.length - dataOffset;
    }
    return WavInfo(
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bits,
      dataOffset: dataOffset,
      dataLength: dataLength,
    );
  }

  /// 44-байтовый заголовок PCM WAV.
  static Uint8List wavHeader(
      int pcmLength, int sampleRate, int channels, int bitsPerSample) {
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final b = BytesBuilder();
    void ascii(String s) => b.add(s.codeUnits);
    void u32(int v) {
      final x = Uint8List(4);
      x.buffer.asByteData().setUint32(0, v, Endian.little);
      b.add(x);
    }

    void u16(int v) {
      final x = Uint8List(2);
      x.buffer.asByteData().setUint16(0, v, Endian.little);
      b.add(x);
    }

    ascii('RIFF');
    u32(36 + pcmLength);
    ascii('WAVE');
    ascii('fmt ');
    u32(16); // размер fmt-чанка
    u16(1); // PCM
    u16(channels);
    u32(sampleRate);
    u32(byteRate);
    u16(blockAlign);
    u16(bitsPerSample);
    ascii('data');
    u32(pcmLength);
    return b.toBytes();
  }

  /// mm-ss для имени файла (двоеточия в именах Android запрещены).
  static String _fmt(double seconds) {
    final total = seconds.round().clamp(0, 359999);
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m-$s';
  }
}
