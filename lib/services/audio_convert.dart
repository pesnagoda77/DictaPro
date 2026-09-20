// Конвертация аудио в WAV 16 кГц моно через нативный канал (task 019).
// Логика перенесена из удалённого VOSK transcription_service.dart
// (stripMp3Tags + convertToWav через MethodChannel 'dictapro/convert'
// — обработчик в MainActivity.kt остался и нужен GigaAM: записи идут
// в WAV с частотой из настроек (до 48 кГц), а импортируемые файлы —
// mp3/m4a/ogg. Движку нужен моно 16 кГц.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class AudioConvert {
  static const _platform = MethodChannel('dictapro/convert');

  /// Возвращает путь к WAV 16 кГц моно.
  /// Если [audioPath] уже такой WAV — возвращает его как есть.
  /// Вызователь обязан удалить временный файл (он в temp-директории).
  static Future<String> toWav16k(String audioPath) async {
    final ext = audioPath.toLowerCase().split('.').last;
    if (ext == 'wav' && await _isWav16kMono(audioPath)) return audioPath;

    String convertPath = audioPath;
    String? cleanMp3;
    if (ext == 'mp3') {
      cleanMp3 = await _stripMp3Tags(audioPath);
      if (cleanMp3 != null) convertPath = cleanMp3;
    }

    // ДИАГНОСТИКА: кладём WAV в доступную папку приложения (Android/data/.../files/tmp),
    // чтобы можно было проверить длительность конвертированного файла снаружи.
    Directory? tempDir;
    try {
      tempDir = await getExternalStorageDirectory();
    } catch (_) {}
    tempDir ??= await getTemporaryDirectory();
    final tempWav =
        '${tempDir.path}/dictapro_16k_${DateTime.now().millisecondsSinceEpoch}.wav';

    final result = await _platform.invokeMethod<Map<dynamic, dynamic>>(
      'convertToWav',
      {'inputPath': convertPath, 'outputPath': tempWav},
    );

    if (cleanMp3 != null) {
      try {
        File(cleanMp3).deleteSync();
      } catch (_) {}
    }

    if (result == null || result['success'] != true) {
      throw Exception(result?['error'] ?? 'Conversion failed');
    }
    return tempWav;
  }

  static Future<bool> _isWav16kMono(String path) async {
    try {
      final f = File(path);
      if (!f.existsSync()) return false;
      final raf = await f.open();
      final head = await raf.read(44);
      await raf.close();
      if (head.length < 44) return false;
      if (String.fromCharCodes(head.sublist(0, 4)) != 'RIFF') return false;
      final reader = ByteData.sublistView(head);
      // fmt-чанк: channels (22), sampleRate (24), bitsPerSample (34)
      final channels = reader.getUint16(22, Endian.little);
      final sampleRate = reader.getUint32(24, Endian.little);
      final bits = reader.getUint16(34, Endian.little);
      return channels == 1 && sampleRate == 16000 && bits == 16;
    } catch (_) {
      return false;
    }
  }

  /// Потоковое удаление ID3-тегов MP3 (без чтения файла целиком).
  /// Возвращает путь к очищенному файлу или null, если тегов нет.
  static Future<String?> _stripMp3Tags(String path) async {
    try {
      final file = File(path);
      final length = await file.length();
      if (length < 10) return null;

      final raf = await file.open();
      int startOffset = 0;
      int endOffset = length;
      try {
        final head = await raf.read(10);
        if (head.length >= 10 &&
            String.fromCharCodes(head.sublist(0, 3)) == 'ID3') {
          final b6 = head[6], b7 = head[7], b8 = head[8], b9 = head[9];
          final tagSize = ((b6 & 0x7F) << 21) |
              ((b7 & 0x7F) << 14) |
              ((b8 & 0x7F) << 7) |
              (b9 & 0x7F);
          startOffset = 10 + tagSize;
        }
        if (length >= 128) {
          await raf.setPosition(length - 128);
          final tail = await raf.read(3);
          if (tail.length == 3 && String.fromCharCodes(tail) == 'TAG') {
            endOffset = length - 128;
          }
        }
      } finally {
        await raf.close();
      }

      if (startOffset == 0 && endOffset == length) return null;
      if (endOffset <= startOffset) {
        throw Exception('MP3 contains only metadata, no audio data found');
      }

      final tempDir = await getTemporaryDirectory();
      final cleanMp3 =
          '${tempDir.path}/temp_clean_${DateTime.now().millisecondsSinceEpoch}.mp3';

      final src = await file.open();
      final dst = File(cleanMp3).openWrite();
      try {
        await src.setPosition(startOffset);
        var remaining = endOffset - startOffset;
        const buf = 262144;
        while (remaining > 0) {
          final toRead = math.min(buf, remaining);
          final chunk = await src.read(toRead);
          if (chunk.isEmpty) break;
          dst.add(chunk);
          remaining -= chunk.length;
        }
      } finally {
        await src.close();
        await dst.close();
      }
      return cleanMp3;
    } catch (_) {
      return null;
    }
  }
}
