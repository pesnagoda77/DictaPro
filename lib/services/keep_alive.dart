import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';

/// Задача 036. Длинная операция (расшифровка файла) должна выживать при
/// выключенном экране. Раньше foreground-служба поднималась только на запись,
/// поэтому система убивала процесс во время расшифровки — Славан потерял
/// результат двухчасового файла на 20-й минуте.
class TranscribeKeepAlive {
  static const _title = 'DictaPro — идёт расшифровка';

  /// Нативные вызовы для задачи 038: фактическое состояние «без ограничений»
  /// и прямое открытие экрана батареи приложения.
  static const _ch = MethodChannel('dictapro/keepalive');

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
  /// с нуля. Task 038: в JSON добавляем путь исходного файла — по нему
  /// стартовый баннер может открыть нужную запись напрямую.
  static Future<void> savePartial(int chunks, String text,
      {String? path}) async {
    try {
      final dir = await _filesDir();
      if (dir == null) return;
      await File('${dir.path}/partial.txt').writeAsString(jsonEncode({
            'chunks': chunks,
            'text': text,
            if (path != null) 'path': path,
          }));
    } catch (_) {}
  }

  /// (число готовых кусков, накопленный текст, путь исходного файла).
  /// Task 038: файлы из сборки 51 писались простым текстом без JSON —
  /// читаем и их: chunks=0 означает «текст есть, номер куска неизвестен»,
  /// интерфейс предлагает хотя бы сохранить текст, а не молчит.
  static Future<(int, String, String?)?> readPartial() async {
    try {
      final dir = await _filesDir();
      if (dir == null) return null;
      final f = File('${dir.path}/partial.txt');
      if (!await f.exists()) return null;
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return null;
      try {
        final map = jsonDecode(raw);
        if (map is Map) {
          final chunks = map['chunks'];
          final text = map['text'];
          if (chunks is int && chunks > 0 && text is String &&
              text.trim().isNotEmpty) {
            return (chunks, text, map['path'] as String?);
          }
        }
      } catch (_) {}
      // Старый формат (≤51): весь файл — это и есть найденный текст.
      return (0, raw, null);
    } catch (_) {
      return null;
    }
  }

  /// Task 038: фактическое состояние «без ограничений».
  /// true — приложение в белом списке батареи; false — ограничено;
  /// null — Android не ответил (старый API/нет канала).
  static Future<bool?> batteryUnrestricted() async {
    try {
      final r = await _ch
          .invokeMethod<int>('batteryUnrestrictedStatus');
      if (r == null) return null;
      return r == 1;
    } catch (_) {
      return null;
    }
  }

  /// Task 038: прямая кнопка «Открыть настройки батареи» — экран батареи
  /// самого приложения (API 26+, фолбэк — карточка приложения).
  static Future<void> openBatterySettings() async {
    try {
      await _ch.invokeMethod('openBatterySettings');
    } catch (_) {}
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
