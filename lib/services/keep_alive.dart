import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';

/// Task 041: единый тег для logcat: adb logcat | grep -i keepalive
void _keepLog(String msg) => debugPrint('[keepalive] $msg');

/// Задача 036. Длинная операция (расшифровка файла) должна выживать при
/// выключенном экране. Раньше foreground-служба поднималась только на запись,
/// поэтому система убивала процесс во время расшифровки — Славан потерял
/// результат двухчасового файла на 20-й минуте.
class TranscribeKeepAlive {
  static const _title = 'DictaPro — идёт расшифровка';

  /// Нативные вызовы для задачи 038: фактическое состояние «без ограничений»
  /// и прямое открытие экрана батареи приложения.
  static const _ch = MethodChannel('dictapro/keepalive');

  /// Task 056: iOS-фон для расшифровки (аудио-сессия + тишина + страховочный
  /// background task). Android продолжает жить на foreground-службе.
  static const _chIos = MethodChannel('dictapro/iosbg');
  static bool _iosBgStarted = false;

  /// Поднимает службу (или обновляет уведомление, если она уже работает).
  static Future<void> start(String text) async {
    try {
      // iOS: foreground-службы нет — держим живой аудиосеанс.
      if (Platform.isIOS) {
        await _chIos.invokeMethod('startSilence');
        await _chIos.invokeMethod('beginTask');
        await _chIos.invokeMethod('keepScreenOn');
        _iosBgStarted = true;
        await writeActiveMarker(text);
        return;
      }
      if (await FlutterForegroundTask.isRunningService) {
        await update(text);
        return;
      }
      final perm = await FlutterForegroundTask.checkNotificationPermission();
      if (perm != NotificationPermission.granted) {
        _keepLog('разрешение на уведомления: $perm — запрашиваем');
        await FlutterForegroundTask.requestNotificationPermission();
      }
      await FlutterForegroundTask.startService(
        notificationTitle: _title,
        notificationText: text,
      );
      // Task 041: раньше ошибки проглатывались молча — «уведомления не было»
      // диагностировать было нечем. Проверяем, что служба реально поднялась.
      final up = await FlutterForegroundTask.isRunningService;
      _keepLog('startService: running=$up perm=$perm');
      await writeActiveMarker(text);
      if (!up) {
        _keepLog('ВНИМАНИЕ: служба не поднялась — фоновая работа под угрозой');
      }
    } catch (e) {
      // не критично: если служба не поднялась, работа продолжается как раньше.
      // Task 041: но молчать об ошибке нельзя — иначе повторяется история
      // «уведомления не было, и никто не знает почему».
      _keepLog('start ОШИБКА: $e');
    }
  }

  /// Маркер «расшифровка идёт»: файл со временем старта и путём записи.
  /// Нужен, чтобы интерфейс показывал живую плашку сразу после запуска —
  /// ещё до того, как будет готов первый кусок текста.
  static Future<File?> _activeFile() async {
    try {
      final dir = await _filesDir();
      if (dir == null) return null;
      return File('${dir.path}/active_job.txt');
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeActiveMarker(String text) async {
    try {
      final f = await _activeFile();
      if (f == null) return;
      await f.writeAsString(jsonEncode({
        'started': DateTime.now().millisecondsSinceEpoch,
        'text': text,
      }));
      _keepLog('маркер активной задачи записан');
    } catch (e) {
      _keepLog('writeActiveMarker ОШИБКА: $e');
    }
  }

  /// Возвращает время старта (мс) и текст этапа, если задача ещё «живая»
  /// (стартовала не позже 6 часов назад и процесс с тех пор не завершил её).
  static Future<(int, String)?> readActiveMarker() async {
    try {
      final f = await _activeFile();
      if (f == null || !await f.exists()) return null;
      final j = jsonDecode(await f.readAsString());
      final started = (j['started'] as num?)?.toInt() ?? 0;
      if (started == 0) return null;
      final age = DateTime.now().millisecondsSinceEpoch - started;
      if (age > 6 * 3600 * 1000) return null;
      return (started, (j['text'] as String?) ?? '');
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearActiveMarker() async {
    try {
      final f = await _activeFile();
      if (f != null && await f.exists()) {
        await f.delete();
        _keepLog('маркер активной задачи убран');
      }
    } catch (_) {}
  }

  static Future<void> update(String text) async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: _title,
          notificationText: text,
        );
      } else {
        // Task 041: update при мёртвой службе — поднимаем заново, иначе
        // прогресс расшифровки невидим в шторке.
        _keepLog('update при мёртвой службе — поднимаем');
        await start(text);
      }
    } catch (e) {
      _keepLog('update ОШИБКА: $e');
    }
  }

  /// Идёт ли сейчас фоновая работа расшифровки (для живой плашки в интерфейсе).
  static Future<bool> isRunning() async {
    try {
      return await FlutterForegroundTask.isRunningService;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    try {
      if (Platform.isIOS && _iosBgStarted) {
        await _chIos.invokeMethod('stopSilence');
        await _chIos.invokeMethod('allowSleep');
        _iosBgStarted = false;
      }
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
        _keepLog('stop: служба остановлена');
      }
      await clearActiveMarker();
    } catch (e) {
      _keepLog('stop ОШИБКА: $e');
    }
  }

  /// Запрос «работать без ограничений» — MIUI без этого душит фон.
  static Future<void> requestBatteryUnrestricted() async {
    try {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } catch (_) {}
  }

  /// Путь к папке приложения, куда пишутся временные файлы.
  /// Task 056: на iOS getExternalStorageDirectory бросает → partial.txt
  /// и active_job.txt никогда не писались, и «Продолжить с куска N» на iOS
  /// молча не работало. Берём applicationSupportDirectory.
  static Future<Directory?> _filesDir() async {
    try {
      if (Platform.isIOS) {
        return await getApplicationSupportDirectory();
      }
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

  /// Частичный результат + состояние задачи (task 045): статус
  /// ('running' во время работы; файл стирается по завершении = 'done')
  /// и время старта — по ним при загрузке отличаем «сейчас считается»
  /// от «оборвалась», не гадая по живости службы.
  static Future<void> savePartial(int chunks, String text,
      {String? path, String status = 'running', int? startedMs}) async {
    try {
      final dir = await _filesDir();
      if (dir == null) return;
      await File('${dir.path}/partial.txt').writeAsString(jsonEncode({
            'chunks': chunks,
            'text': text,
            if (path != null) 'path': path,
            'status': status,
            if (startedMs != null) 'startedMs': startedMs,
          }));
    } catch (_) {}
  }

  /// (число готовых кусков, накопленный текст, путь исходного файла,
  /// статус, время старта мс).
  /// Task 038: файлы из сборки 51 писались простым текстом без JSON —
  /// читаем и их: chunks=0 означает «текст есть, номер куска неизвестен»,
  /// интерфейс предлагает хотя бы сохранить текст, а не молчит.
  /// Task 045: старые JSON без status/startedMs читаем как 'interrupted' —
  /// это и есть следы оборванного прогона.
  static Future<(int, String, String?, String, int)?> readPartial() async {
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
            return (
              chunks,
              text,
              map['path'] as String?,
              (map['status'] as String?) ?? 'interrupted',
              (map['startedMs'] as num?)?.toInt() ?? 0,
            );
          }
        }
      } catch (_) {}
      // Старый формат (≤51): весь файл — это и есть найденный текст.
      return (0, raw, null, 'interrupted', 0);
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
