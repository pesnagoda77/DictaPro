// Task 116 (Славан, 25.10): модуль усиления тихих записей.
// ОТДЕЛЬНЫЙ модуль: ничего не меняет в существующем пайплайне —
// работает ТОЛЬКО с временной копией для движка распознавания и ТОЛЬКО
// когда запись явно тихая (RMS ниже порога). Оригиналы не трогает.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

class AudioNormalizer {
  static const _boxName = 'settings';
  static const _keyEnabled = 'agc_boost';

  static const double rmsQuietThreshold = -38.0;
  static const double rmsTarget = -26.0;
  static const double maxGainDb = 30.0;
  static const double peakCeilingDb = -1.5;

  static bool? _enabledCache;
  static String lastReport = '';

  static Future<bool> isEnabled() async {
    if (_enabledCache != null) return _enabledCache!;
    try {
      final box = Hive.isBoxOpen(_boxName)
          ? Hive.box<dynamic>(_boxName)
          : await Hive.openBox<dynamic>(_boxName);
      final v = box.get(_keyEnabled, defaultValue: true);
      _enabledCache = (v as bool?) ?? true;
    } catch (_) {
      _enabledCache = true;
    }
    return _enabledCache!;
  }

  /// Славан: галка «Улучшить качество звука» в карточке текста.
  static Future<void> setEnabled(bool v) async {
    _enabledCache = v;
    try {
      final box = Hive.isBoxOpen(_boxName)
          ? Hive.box<dynamic>(_boxName)
          : await Hive.openBox<dynamic>(_boxName);
      await box.put(_keyEnabled, v);
    } catch (_) {}
  }

  static void invalidateToggle() => _enabledCache = null;

  /// Если WAV тихий — создаёт УСИЛЕННУЮ КОПИЮ '<имя>_boosted.wav' рядом
  /// и возвращает её путь. Иначе null. Вход: WAV PCM16.
  static Future<String?> boostIfQuiet(String wavPath) async {
    lastReport = '';
    try {
      if (!await isEnabled()) {
        lastReport = 'модуль выключен';
        return null;
      }
      final f = File(wavPath);
      if (!await f.exists()) return null;
      final size = await f.length();
      if (size < 44 + 32000) return null; // короче секунды — не трогаем

      final raf = await f.open();
      try {
        final head = await raf.read(65536);
        if (head.length < 44 ||
            String.fromCharCodes(head.sublist(0, 4)) != 'RIFF') {
          return null;
        }
        var rate = 0, channels = 0, bits = 0, dataOffset = -1;
        var pos = 12;
        while (pos + 8 <= head.length) {
          final id = String.fromCharCodes(head.sublist(pos, pos + 4));
          final sz = head[pos + 4] |
              (head[pos + 5] << 8) |
              (head[pos + 6] << 16) |
              (head[pos + 7] << 24);
          final body = pos + 8;
          if (id == 'fmt ' && body + 16 <= head.length) {
            channels = head[body + 2] | (head[body + 3] << 8);
            rate = head[body + 4] |
                (head[body + 5] << 8) |
                (head[body + 6] << 16) |
                (head[body + 7] << 24);
            bits = head[body + 14] | (head[body + 15] << 8);
          } else if (id == 'data') {
            dataOffset = body;
            break;
          }
          pos = body + sz + (sz.isOdd ? 1 : 0);
        }
        if (dataOffset < 0 || bits != 16 || channels <= 0 || rate <= 0) {
          return null;
        }

        // Замер уровня: до 8 МБ с начала данных.
        await raf.setPosition(dataOffset);
        final probe = await raf.read(8 * 1024 * 1024);
        var peak = 0;
        var sumSq = 0.0;
        var n = 0;
        final probeInts = Int16List.view(
            probe.buffer, probe.offsetInBytes, probe.length ~/ 2);
        for (var i = 0; i + channels <= probeInts.length; i += channels * 4) {
          for (var c = 0; c < channels; c++) {
            final s = probeInts[i + c];
            final a = s < 0 ? -s : s;
            if (a > peak) peak = a;
            sumSq += s * s;
            n++;
          }
        }
        if (n == 0) return null;
        final rmsDb = _dbOfAmp(math.sqrt(sumSq / n));
        final peakDb = _dbOfAmp(peak.toDouble());
        if (rmsDb >= rmsQuietThreshold) {
          lastReport = 'тихих нет (RMS ${rmsDb.toStringAsFixed(1)} dBFS)';
          return null; // нормальная запись — не трогаем
        }

        var gainDb = (rmsTarget - rmsDb).clamp(0.0, maxGainDb);
        final maxByPeak = peakCeilingDb - peakDb;
        if (gainDb > maxByPeak) gainDb = maxByPeak;
        if (gainDb <= 0.5) {
          lastReport = 'усиление не требуется (пик $peakDb dBFS)';
          return null;
        }
        final gain = math.pow(10.0, gainDb / 20.0).toDouble();

        final dot = wavPath.lastIndexOf('.');
        final outPath = dot < 0
            ? '${wavPath}_boosted.wav'
            : '${wavPath.substring(0, dot)}_boosted.wav';
        final outFile = File(outPath);
        final sink = outFile.openWrite();
        try {
          sink.add(head.sublist(0, dataOffset));
          await raf.setPosition(dataOffset);
          const chunkBytes = 1 << 20;
          while (true) {
            final chunk = await raf.read(chunkBytes);
            if (chunk.isEmpty) break;
            final ints = Int16List.view(
                chunk.buffer, chunk.offsetInBytes, chunk.length ~/ 2);
            for (var i = 0; i < ints.length; i++) {
              var v = (ints[i] * gain).round();
              if (v > 32767) v = 32767;
              if (v < -32768) v = -32768;
              ints[i] = v;
            }
            sink.add(chunk);
          }
        } finally {
          await sink.close();
          await raf.close();
        }
        debugPrint('[agc] усиление +${gainDb.toStringAsFixed(1)} дБ '
            '(RMS ${rmsDb.toStringAsFixed(1)} → $rmsTarget dBFS): $outPath');
        lastReport =
            'усиление +${gainDb.toStringAsFixed(1)} дБ (RMS ${rmsDb.toStringAsFixed(1)})';
        return outPath;
      } catch (e) {
        debugPrint('[agc] ошибка: $e');
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  static double _dbOfAmp(num amp) {
    final v = amp / 32768.0;
    if (v <= 0) return -120;
    return 20 * math.log(v) / math.ln10;
  }
}
