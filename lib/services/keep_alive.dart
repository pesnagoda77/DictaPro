import 'dart:convert';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';

/// Задача 036. Длинная операция (расшифровка файла) должна выживать при
/// выключенном экране. Раньше foreground-служба поднималась только на запись,
/// поэтому система убивала процесс во время расшифровки — Славан потерял
/// результат двухчасового файла на 20-й минуте.
class TranscribeKeepAlive {
  static const _title = 'DictaPro — идёт расшифровка';

  /// Поднимает службу (или обновляет уведомление, если она уже работает).
  static Future<void> start(String text) async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await update(text);
        return;
      }
      final perm = await FlutterForegroundTask.checkNotificationPermission();
      if (perm != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      await FlutterForegroundTask.startService(
        notificationTitle: _title,
        notificationText: text,
      );
    } catch (_) {
      // не критично: если служба не поднялась, работа продолжается как раньше
    }
  }

  static Future<void> update(String text) async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: _title,
          notificationText: text,
        );
      }
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {}
  }

  /// Запрос «работать без ограничений» — MIUI без этого душит фон.
  static Future<void> requestBatteryUnrestricted() async {
    try {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } catch (_) {}
  }

  /// Путь к папке приложения, куда пишутся временные файлы.
  static Future<Directory?> _filesDir() async {
    try {
      return await getExternalStorageDirectory();
    } catch (_) {
      return null;
    }
  }

  static bool _isTemp(String name) =>
      name.startsWith('dictapro_16k_') ||
      name.endsWith('.tmp.pcm') ||
      name.endsWith('.tmp.wav');

  /// Задача 036: уборка мусора сразу после операции.
  /// Временные файлы конвертации больше не остаются на телефоне
  /// (20.09 в папке накопилось ~890 МБ).
  static Future<int> cleanupTempFiles({bool onlyOld = false}) async {
    final dir = await _filesDir();
    if (dir == null) return 0;
    var freed = 0;
    try {
      await for (final e in dir.list()) {
        final name = e.path.split(Platform.pathSeparator).last;
        if (!_isTemp(name)) continue;
        if (onlyOld) {
          final st = await e.stat();
          if (DateTime.now().difference(st.modified) < const Duration(hours: 24)) {
            continue;
          }
        }
        try {
          final f = File(e.path);
          freed += await f.length();
          await f.delete();
        } catch (_) {}
      }
    } catch (_) {}
    return freed;
  }

  /// Проверка при старте: подчистить остатки прошлых прогонов.
  static Future<void> sweepOldTemp() async {
    await cleanupTempFiles(onlyOld: true);
  }

  /// Частичный результат расшифровки: пишем по ходу, чтобы выгрузка процесса
  /// не означала потерю всего текста.
  /// Task 036 (доп.): формат JSON с числом готовых кусков — по нему при
  /// повторном запуске предлагаем «Продолжить с куска N», а не начинаем
  /// с нуля.
  static Future<void> savePartial(int chunks, String text) async {
    try {
      final dir = await _filesDir();
      if (dir == null) return;
      await File('${dir.path}/partial.txt')
          .writeAsString(jsonEncode({'chunks': chunks, 'text': text}));
    } catch (_) {}
  }

  /// Число готовых кусков и накопленный текст прерванной расшифровки.
  /// null — продолжать нечего (нет файла, битый формат или старый
  /// plain-text вариант без счётчика кусков).
  static Future<(int, String)?> readPartial() async {
    try {
      final dir = await _filesDir();
      if (dir == null) return null;
      final f = File('${dir.path}/partial.txt');
      if (!await f.exists()) return null;
      final map = jsonDecode(await f.readAsString());
      if (map is! Map) return null;
      final chunks = map['chunks'];
      final text = map['text'];
      if (chunks is! int || chunks <= 0 || text is! String) return null;
      if (text.trim().isEmpty) return null;
      return (chunks, text);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearPartial() async {
    try {
      final dir = await _filesDir();
      if (dir == null) return;
      final f = File('${dir.path}/partial.txt');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Размер занятого временного мусора — для настроек.
  static Future<int> tempSize() async {
    final dir = await _filesDir();
    if (dir == null) return 0;
    var size = 0;
    try {
      await for (final e in dir.list()) {
        final name = e.path.split(Platform.pathSeparator).last;
        if (!_isTemp(name)) continue;
        size += await File(e.path).length();
      }
    } catch (_) {}
    return size;
  }
}
