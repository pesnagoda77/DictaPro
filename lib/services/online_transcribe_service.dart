import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'stt_provider.dart';

/// Онлайн-транскрипция: режет WAV (16 кГц моно 16 бит) на куски и
/// отправляет провайдеру по очереди. Память константна (по одному куску).
class OnlineTranscribeService {
  /// Куски по ~7 минут (16кГц mono 16бит = 32 КБ/с → 7 мин ≈ 13,4 МБ,
  /// проходит лимит Groq 25 МБ). Перекрытие 2 секунды для связности.
  static const int _chunkSeconds = 420;
  static const int _overlapSeconds = 2;
  static const int _sampleRate = 16000;
  static const int _bytesPerSecond = _sampleRate * 2;

  /// Возвращает полный текст. [onProgress] — 0.0..1.0.
  static Future<String> transcribe(
    String wavPath, {
    required SttProvider provider,
    required String apiKey,
    void Function(double progress, int chunkIndex, int chunkCount)? onProgress,
  }) async {
    final file = File(wavPath);
    final info = await _readWavHeader(file);
    final totalBytes = info.dataSize;
    final chunkBytes = _chunkSeconds * _bytesPerSecond;
    final overlapBytes = _overlapSeconds * _bytesPerSecond;

    // Список диапазонов (start, length) в области данных
    final ranges = <List<int>>[];
    var offset = 0;
    while (offset < totalBytes) {
      final len = math.min(chunkBytes, totalBytes - offset);
      ranges.add([offset, len]);
      if (offset + len >= totalBytes) break;
      offset += chunkBytes - overlapBytes;
    }

    final raf = await file.open();
    final texts = <String>[];
    try {
      final tmpDir = Directory.systemTemp;
      for (var i = 0; i < ranges.length; i++) {
        final start = ranges[i][0];
        final len = ranges[i][1];
        await raf.setPosition(info.dataOffset + start);
        final pcm = await raf.read(len);

        // Собираем валидный WAV для отправки
        final chunkFile = File(
            '${tmpDir.path}/stt_chunk_${DateTime.now().millisecondsSinceEpoch}_$i.wav');
        await chunkFile.writeAsBytes(_buildWav(pcm));

        String text = '';
        var attempt = 0;
        while (attempt < 3) {
          try {
            text = await provider.transcribe(chunkFile, apiKey);
            break;
          } catch (e) {
            attempt++;
            if (attempt >= 3) rethrow;
            await Future.delayed(Duration(seconds: 2 * attempt));
          }
        }
        try {
          await chunkFile.delete();
        } catch (_) {}
        texts.add(text);
        onProgress?.call((i + 1) / ranges.length, i + 1, ranges.length);
      }
    } finally {
      await raf.close();
    }
    return texts.where((t) => t.isNotEmpty).join(' ').trim();
  }

  static Future<_WavInfo> _readWavHeader(File f) async {
    final raf = await f.open();
    try {
      final head = await raf.read(65536);
      final bd = ByteData.sublistView(head);
      var pos = 12;
      while (pos + 8 <= head.length) {
        final id = String.fromCharCodes(head.sublist(pos, pos + 4));
        final size = bd.getUint32(pos + 4, Endian.little);
        if (id == 'data') {
          return _WavInfo(pos + 8, math.min(size, (await f.length()) - (pos + 8)));
        }
        pos += 8 + size;
      }
      throw SttException('Не удалось прочитать WAV-заголовок');
    } finally {
      await raf.close();
    }
  }

  static Uint8List _buildWav(Uint8List pcm) {
    final header = BytesBuilder();
    void str(String s) => header.add(s.codeUnits);
    void u32(int v) {
      final b = ByteData(4)..setUint32(0, v, Endian.little);
      header.add(b.buffer.asUint8List());
    }

    void u16(int v) {
      final b = ByteData(2)..setUint16(0, v, Endian.little);
      header.add(b.buffer.asUint8List());
    }

    str('RIFF');
    u32(36 + pcm.length);
    str('WAVE');
    str('fmt ');
    u32(16);
    u16(1); // PCM
    u16(1); // mono
    u32(_sampleRate);
    u32(_sampleRate * 2); // byte rate
    u16(2); // block align
    u16(16); // bits
    str('data');
    u32(pcm.length);
    final out = BytesBuilder();
    out.add(header.toBytes());
    out.add(pcm);
    return out.toBytes();
  }
}

class _WavInfo {
  final int dataOffset;
  final int dataSize;
  _WavInfo(this.dataOffset, this.dataSize);
}
