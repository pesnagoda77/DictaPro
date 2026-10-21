// Task 111 v4 (21.10 вечер): надёжные фрагменты из ЛЮБЫХ форматов.
//
// Урок +98: побитовая резка контейнеров (m4a/ogg/flac) даёт битые файлы —
// на другом устройстве не играют (повреждённые боксы MP4/страницы OGG).
//
// Новая стратегия: перекодирование нативным декодером платформы.
// Android: MediaExtractor+MediaCodec → PCM → пишем WAV (гарантированно
// играбельный на всём). iOS: AVAssetExportSession (позже).
// Это медленнее побитовой (реальное декодирование), но файл всегда валидный.
// WAV-исходники режутся по-прежнему байт-точно без перекодирования.
// MP3 — копированием кадров (проверено, играет).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../audio_service.dart';

/// Метаданные WAV-файла, нужные для байтовой резки.
class WavInfo {
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int dataOffset;
  final int dataLength;

  const WavInfo({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataLength,
  });

  double get byteRate => sampleRate * channels * (bitsPerSample ~/ 8).toDouble();

  double get durationSec => byteRate > 0 ? dataLength / byteRate : 0;
}

class AudioFragmentService {
  /// Отступ с обеих сторон, чтобы не обрезать начало/конец слова.
  static const int paddingMs = 150;

  /// Запасной размер, если у старой записи нет таймкодов (end <= start).
  static const double fallbackSec = 15;

  /// Причина последней неудачи — показываем в интерфейсе для диагностики.
  static String? lastError;

  static const _convertChannel = MethodChannel('dictapro/convert');

  static String? _fail(String reason) {
    lastError = reason;
    // ignore: avoid_print
    print('[fragment] FAIL: $reason');
    return null;
  }

  /// Вырезает фрагмент [startSec]…[endSec] из записи [storedPath]
  /// и сохраняет его в папку записей. Возвращает путь к файлу или null.
  static Future<String?> exportFragment({
    required String storedPath,
    required double startSec,
    required double endSec,
  }) async {
    lastError = null;
    final resolved = await AudioService.resolveFilePath(storedPath);
    final src = File(resolved);
    // ignore: avoid_print
    print('[fragment] stored=$storedPath resolved=$resolved');
    if (!await src.exists()) {
      return _fail('файл записи не найден: $resolved');
    }

    final raf = await src.open();
    try {
      final head = await raf.read(65536);
      final kind = detectFormat(head);

      switch (kind) {
        case MediaKind.wav:
          return await _exportWav(raf, head, startSec, endSec);
        case MediaKind.mp3:
          return await _exportMp3(raf, head, startSec, endSec, src);
        // Контейнерные форматы: только перекодирование — побитая резка
        // рождает невалидные файлы (урок +98).
        case MediaKind.mp4:
        case MediaKind.ogg:
        case MediaKind.flac:
          return await _exportTranscode(
              resolved, startSec, endSec, kind, src);
        case MediaKind.unknown:
          final sig = head.length >= 12
              ? '${String.fromCharCodes(head.sublist(0, 4))} / '
                  '${String.fromCharCodes(head.sublist(4, 8))}'
              : 'short';
          return _fail('формат не распознан ($sig). Конвертируйте файл в WAV '
              'или MP3 и импортируйте снова');
      }
    } finally {
      await raf.close();
    }
  }

  // ───────────────────────── WAV ─────────────────────────

  static Future<String?> _exportWav(RandomAccessFile raf, Uint8List head,
      double startSec, double endSec) async {
    final info = parseWav(head);
    if (info == null) return _fail('WAV: заголовок не разобран');

    final pad = paddingMs / 1000.0;
    var from = (startSec - pad).clamp(0.0, info.durationSec);
    var to = (endSec + pad).clamp(0.0, info.durationSec);

    if (to <= from) {
      from = startSec.clamp(0.0, info.durationSec);
      to = (from + fallbackSec).clamp(0.0, info.durationSec);
    }
    if (to <= from) {
      return _fail('пустой диапазон: from=${from.toStringAsFixed(2)} '
          'to=${to.toStringAsFixed(2)} (start=$startSec end=$endSec, '
          'dur=${info.durationSec.toStringAsFixed(2)})');
    }

    final startByte = info.dataOffset + (from * info.byteRate).round();
    var endByte = info.dataOffset + (to * info.byteRate).round();
    final dataEnd = info.dataOffset + info.dataLength;
    if (endByte > dataEnd) endByte = dataEnd;
    final frame = info.channels * (info.bitsPerSample ~/ 8);
    if (frame > 1) {
      endByte = startByte + ((endByte - startByte) ~/ frame) * frame;
    }
    if (endByte <= startByte) return _fail('пустые байты: $startByte…$endByte');

    final dir = await AudioService.recordingsDir();
    final outPath = '${dir.path}/фрагмент ${_fmt(from)}–${_fmt(to)}.wav';

    final sink = File(outPath).openWrite();
    try {
      sink.add(wavHeader(endByte - startByte, info.sampleRate, info.channels,
          info.bitsPerSample));
      await _copyRange(raf, sink, startByte, endByte);
    } finally {
      await sink.close();
    }
    return outPath;
  }

  // ───────────────────────── MP3 ─────────────────────────

  static Future<String?> _exportMp3(RandomAccessFile raf, Uint8List head,
      double startSec, double endSec, File src) async {
    final fileLen = await src.length();
    var firstFrame = head.length >= 10 &&
            String.fromCharCodes(head.sublist(0, 3)) == 'ID3'
        ? ((head[6] << 21) | (head[7] << 14) | (head[8] << 7) | head[9]) + 10
        : mp3FirstFrame(head);
    await raf.setPosition(firstFrame);
    final probe = await raf.read(4096);
    final br = mp3Bitrate(probe);
    if (br <= 0) return _fail('MP3: не найден кадр для определения битрейта');
    final audioLen = fileLen - firstFrame;
    final durationSec = audioLen * 8 / br;
    // ignore: avoid_print
    print('[fragment] mp3: bitrate=${br / 1000}kbps dur~${durationSec.toStringAsFixed(1)}s');

    final pad = paddingMs / 1000.0;
    var from = (startSec - pad).clamp(0.0, durationSec);
    var to = (endSec + pad).clamp(0.0, durationSec);
    if (to <= from) {
      from = startSec.clamp(0.0, durationSec);
      to = (from + fallbackSec).clamp(0.0, durationSec);
    }
    if (to <= from) return _fail('пустой диапазон MP3');

    final startByte = firstFrame + (from * br / 8).round();
    var endByte = firstFrame + (to * br / 8).round();
    if (endByte > fileLen) endByte = fileLen;
    final back = startByte - 2048 > firstFrame ? 2048 : (startByte - firstFrame);
    await raf.setPosition(startByte - back);
    final sync = await raf.read(back + 4);
    var alignedStart = startByte;
    for (var i = sync.length - 4; i >= 0; i--) {
      if (sync[i] == 0xFF && (sync[i + 1] & 0xE0) == 0xE0) {
        alignedStart = startByte - (sync.length - 4 - i);
        break;
      }
    }
    if (alignedStart >= endByte) return _fail('MP3: пустой диапазон');

    final dir = await AudioService.recordingsDir();
    final outPath = '${dir.path}/фрагмент ${_fmt(from)}–${_fmt(to)}.mp3';

    final sink = File(outPath).openWrite();
    try {
      if (firstFrame > 0 && firstFrame <= head.length) {
        sink.add(head.sublist(0, firstFrame)); // ID3v2 как есть
      }
      await _copyRange(raf, sink, alignedStart, endByte);
    } finally {
      await sink.close();
    }
    return outPath;
  }

  // ─────── M4A/AAC, OGG, FLAC: перекодирование в WAV через натив ───────

  static Future<String?> _exportTranscode(String resolvedPath,
      double startSec, double endSec, MediaKind kind, File src) async {
    final fileLen = await src.length();
    const fallbackKbps = 128;
    final estDurationSec = fileLen * 8 / (fallbackKbps * 1000);

    final pad = paddingMs / 1000.0;
    final fromMs = ((startSec - pad).clamp(0.0, estDurationSec) * 1000).round();
    var toMs = ((endSec + pad).clamp(0.0, estDurationSec) * 1000).round();
    if (toMs - fromMs < 500) toMs = fromMs + (fallbackSec * 1000).round();

    // Нативная конвертация диапазона: Android MediaExtractor+MediaCodec
    // декодирует вход в PCM WAV (моно 16к не обязательно — сохраняем родные
    // частоту/каналы, WAV-заголовок пишем по факту). Обработчик: MainActivity.
    final String wavTmp;
    try {
      wavTmp = await _convertChannel.invokeMethod<String>(
        'extractFragmentWav',
        {
          'path': resolvedPath,
          'fromMs': fromMs,
          'toMs': toMs,
        },
      ) ?? '';
    } on PlatformException catch (e) {
      return _fail('нативная конвертация ${kind.name}: ${e.code} ${e.message}');
    }
    if (wavTmp.isEmpty || !await File(wavTmp).exists()) {
      return _fail('нативная конвертация не создала файл');
    }

    final dir = await AudioService.recordingsDir();
    final outPath =
        '${dir.path}/фрагмент ${_fmt(fromMs / 1000)}–${_fmt(toMs / 1000)}.wav';
    await File(wavTmp).rename(outPath);
    return outPath;
  }

  // ───────────────────────── утилиты ─────────────────────────

  /// MP3: смещение первого кадра, если нет ID3.
  static int mp3FirstFrame(Uint8List b) {
    for (var i = 0; i + 2 < b.length && i < 4096; i++) {
      if (b[i] == 0xFF && (b[i + 1] & 0xE0) == 0xE0) return i;
    }
    return 0;
  }

  /// MP3 битрейт из первого кадра (MPEG-1 Layer III таблица, kbps).
  static int mp3Bitrate(Uint8List b) {
    for (var i = 0; i + 4 <= b.length; i++) {
      if (b[i] == 0xFF && (b[i + 1] & 0xE0) == 0xE0) {
        final bitrateIdx = (b[i + 2] >> 4) & 0x0F;
        const table = [
          0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0
        ];
        if (bitrateIdx > 0 && bitrateIdx < 15) return table[bitrateIdx] * 1000;
      }
    }
    return 0;
  }

  /// Определяет формат по голове файла.
  static MediaKind detectFormat(Uint8List b) {
    if (b.length >= 12 &&
        String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(b.sublist(8, 12)) == 'WAVE') {
      return MediaKind.wav;
    }
    if (b.length >= 10 && String.fromCharCodes(b.sublist(0, 3)) == 'ID3') {
      return MediaKind.mp3;
    }
    if (b.length >= 12 && String.fromCharCodes(b.sublist(4, 8)) == 'ftyp') {
      return MediaKind.mp4; // M4A/AAC/MP4
    }
    if (b.length >= 4 && String.fromCharCodes(b.sublist(0, 4)) == 'OggS') {
      return MediaKind.ogg; // OGG/OPUS
    }
    if (b.length >= 4 && String.fromCharCodes(b.sublist(0, 4)) == 'fLaC') {
      return MediaKind.flac;
    }
    for (var i = 0; i + 2 < b.length && i < 4096; i++) {
      if (b[i] == 0xFF && (b[i + 1] & 0xE0) == 0xE0) {
        return MediaKind.mp3;
      }
    }
    return MediaKind.unknown;
  }

  static Future<void> _copyRange(
      RandomAccessFile raf, IOSink sink, int from, int to) async {
    const chunkSize = 1 << 20; // 1 МБ
    var pos = from;
    await raf.setPosition(pos);
    while (pos < to) {
      final want = (to - pos) > chunkSize ? chunkSize : (to - pos);
      final buf = await raf.read(want);
      if (buf.isEmpty) break;
      sink.add(buf);
      pos += buf.length;
    }
    await sink.flush();
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
    u32(16);
    u16(1);
    u16(channels);
    u32(sampleRate);
    u32(byteRate);
    u16(blockAlign);
    u16(bitsPerSample);
    ascii('data');
    u32(pcmLength);
    return b.toBytes();
  }

  static String _fmt(double seconds) {
    final total = seconds.round().clamp(0, 359999);
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m-$s';
  }
}



/// Форматы, которые умеет резать сервис.
enum MediaKind { wav, mp3, mp4, ogg, flac, unknown }
