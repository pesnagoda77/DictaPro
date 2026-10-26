import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hive/hive.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'services/wav_header_fixer.dart';
import 'services/keep_alive.dart';
import 'settings_page.dart';
import 'dart:math' as math;
import 'app_strings.dart';

export 'models/transcription.dart' show DialogueSegment;

class Recording {
  String id;
  String filePath;
  DateTime createdAt;
  int durationMs;
  int fileSize;
  String? title;
  String? transcription;
  /// Термины ЭТОЙ записи (глоссарий GigaAM) — вводятся в карточке текста
  /// («Термины этой записи» → «Заново»), хранятся вместе с записью.
  String? hotwords;
  List<Map<String, dynamic>>? segments;
  bool isFavorite;

  List<String>? tags;
  String? summary;

  /// Задача 26.10 (Славан): на каком языке собран [summary].
  /// Меняется вместе с языком интерфейса — при расхождении итог
  /// пересобирается автоматически (иначе текст оставался русским).
  String? summaryLang;
  List<String>? decisions;
  List<Map<String, dynamic>>? speakerStats;

  /// Task 116 П.2: content:// URI в публичной Documents/DictaPro/Записи
  /// (MediaStore). Файл по filePath на API 29+ недоступен напрямую
  /// (scoped storage) — чтение/проигрывание идёт через материализацию
  /// из contentUri. null — запись ещё в app-private (миграция не прошла)
  /// или платформа без scoped storage (≤API 28, iOS).
  String? contentUri;

  Recording({
    required this.id,
    required this.filePath,
    required this.createdAt,
    required this.durationMs,
    required this.fileSize,
    this.title,
    this.transcription,
    this.hotwords,
    this.segments,
    this.isFavorite = false,
    this.tags,
    this.summary,
    this.summaryLang,
    this.decisions,
    this.speakerStats,
    this.contentUri,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'filePath': filePath,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'durationMs': durationMs,
        'fileSize': fileSize,
        'title': title,
        'transcription': transcription,
        'hotwords': hotwords,
        'segments': segments,
        'isFavorite': isFavorite,
        'tags': tags,
        'summary': summary,
        'summaryLang': summaryLang,
        'decisions': decisions,
        'speakerStats': speakerStats?.map((s) => s.map((k, v) => MapEntry(k, v.toString()))).toList(),
        'contentUri': contentUri,
      };

  factory Recording.fromMap(Map<String, dynamic> map) => Recording(
        id: map['id'] as String,
        filePath: map['filePath'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
        durationMs: map['durationMs'] as int,
        fileSize: map['fileSize'] as int,
        title: map['title'] as String?,
        transcription: map['transcription'] as String?,
        hotwords: map['hotwords'] as String?,
        segments: map['segments'] != null
            ? (map['segments'] as List)
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList()
            : null,
        isFavorite: map['isFavorite'] as bool? ?? false,
        tags: map['tags'] != null
            ? (map['tags'] as List).cast<String>()
            : null,
        summary: map['summary'] as String?,
        summaryLang: map['summaryLang'] as String?,
        decisions: map['decisions'] != null
            ? (map['decisions'] as List).cast<String>()
            : null,
        speakerStats: map['speakerStats'] != null
            ? (map['speakerStats'] as List)
                .map((item) => (item as Map).map((k, v) => MapEntry<String, dynamic>(k as String, v)))
                .toList()
            : null,
        contentUri: map['contentUri'] as String?,
      );
}

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;

  /// Task 116 П.2: нативный канал публикации записей в публичную
  /// Documents/DictaPro/Записи через MediaStore (scoped storage).
  static const MethodChannel _recordingsChannel =
      MethodChannel('dictapro/recordings');

  /// Task 116 П.2: куда отдаём записи пользователю (публичная папка).
  /// Тот же путь, что показываем в настройках и открываем по «Открыть».
  static const String publicRecordingsRelativePath =
      'Documents/DictaPro/Записи';

  static String get publicRecordingsDisplayPath =>
      '/storage/emulated/0/$publicRecordingsRelativePath';

  AudioService._internal();

  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  bool _isInit = false;
  Box<Map>? _box;
  DateTime? _startTime;
  Timer? _sleepTimer;
  int? _sleepDurationMinutes;

  // Live-превью расшифровки при записи убрано вместе с VOSK (task 019):
  // батч-расшифровка GigaAM после остановки и так лучше по качеству.

  /// Путь к файлу записи, устойчивый к переустановке приложения.
  ///
  /// На iOS папка документов содержит UUID контейнера, который МЕНЯЕТСЯ при
  /// Task 112: путь к папке записей. Android 10+ — публичная Documents/DictaPro/Записи
  /// через MediaStore; ≤9 — внешнее хранилище; iOS — Documents/DictaPro/Записи.
  static Future<Directory> recordingsDir() async {
    if (Platform.isAndroid) {
      final sdk = await _androidSdk();
      if (sdk >= 29) {
        // Android 10+: MediaStore путь (виртуальный, через ContentResolver).
        return Directory('${await _mediaStoreRecordingsPath()}');
      } else {
        // Android ≤9: прямой путь на внешнее хранилище.
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          final dir = Directory('${ext.path}/DictaPro/Записи');
          await dir.create(recursive: true);
          return dir;
        }
      }
    }
    // iOS и fallback — Documents/DictaPro/Записи.
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/DictaPro/Записи');
    await dir.create(recursive: true);
    return dir;
  }

  /// Task 112: Android SDK version.
  static Future<int> _androidSdk() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return info.version.sdkInt;
    } catch (_) {
      return 0;
    }
  }

  /// Task 112: путь для MediaStore (Android 10+).
  /// Используем Environment.DIRECTORY_DOCUMENTS + RELATIVE_PATH.
  static Future<String> _mediaStoreRecordingsPath() async {
    // Для record plugin путь должен быть реальным файловым путём.
    // На Android 10+ app-specific external files не требуют разрешений
    // и видны в Files через MediaStore при сканировании.
    final ext = await getExternalStorageDirectory();
    if (ext != null) {
      final dir = Directory('${ext.path}/DictaPro/Записи');
      await dir.create(recursive: true);
      return dir.path;
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/DictaPro/Записи');
    await dir.create(recursive: true);
    return dir.path;
  }

  /// Task 112: понятное имя файла — дата_время.
  static String _recordingFileName() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final mo = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final h = now.hour.toString().padLeft(2, '0');
    final mi = now.minute.toString().padLeft(2, '0');
    return '${y}-${mo}-${d}_${h}-${mi}_Запись.wav';
  }

  /// каждой переустановке. Если в базе сохранён старый абсолютный путь, файл
  /// «не находится», хотя лежит рядом. Поэтому: если сохранённый путь не
  /// существует — берём из него только имя файла и подставляем текущую папку.
  /// Task 116 П.2: абсолютный путь к СОДЕРЖИМОМУ записи для плеера,
  /// конвертера и шаринга. Если запись живёт в публичной коллекции
  /// (contentUri != null), scoped storage запрещает читать её по пути
  /// напрямую — нативно копируем во временный файл в app-кэш.
  /// Кэш чистится при каждом init — копии не копятся между сессиями.
  /// Task 116 (Славан): файл, открытый «в DictaPro» из проводника.
  /// Возвращает {uri, name} или null (нечего открывать).
  static Future<Map<String, String>?> takePendingOpenFile() async {
    if (!Platform.isAndroid) return null;
    try {
      final out = await _recordingsChannel
          .invokeMethod<Map<dynamic, dynamic>>('takePendingOpenFile');
      if (out == null) return null;
      return {
        'uri': out['uri']?.toString() ?? '',
        'name': out['name']?.toString() ?? '',
      };
    } catch (e) {
      debugPrint('[recordings] takePendingOpenFile: $e');
      return null;
    }
  }

  /// Task 116: материализовать произвольный content:// uri (открыт снаружи).
  /// Task 116 (Славан): полный список файлов папки записей.
  /// Android — через MediaStore (все файлы); iOS — по файловой системе.
  /// Каждый элемент: name, path, uri ('' на iOS), size, dateMs.
  static Future<List<Map<String, String>>> listPublicFolder() async {
    final out = <Map<String, String>>[];
    if (Platform.isAndroid) {
      try {
        final raw = await _recordingsChannel
            .invokeMethod<List<dynamic>>('listRecordingsFolder');
        for (final e in raw ?? <dynamic>[]) {
          final m = Map<String, dynamic>.from(e as Map);
          out.add({
            'name': m['name']?.toString() ?? '',
            'path': m['path']?.toString() ?? '',
            'uri': m['uri']?.toString() ?? '',
            'size': m['size']?.toString() ?? '0',
            'dateMs': m['dateMs']?.toString() ?? '0',
          });
        }
      } catch (e) {
        debugPrint('[recordings] listPublicFolder: $e');
      }
      return out;
    }
    // iOS: файловая система.
    try {
      final dir = await recordingsDir();
      if (await dir.exists()) {
        await for (final e in dir.list()) {
          if (e is File) {
            final st = e.statSync();
            out.add({
              'name': e.uri.pathSegments.last,
              'path': e.path,
              'uri': '',
              'size': '${st.size}',
              'dateMs': '${st.modified.millisecondsSinceEpoch}',
            });
          }
        }
      }
    } catch (_) {}
    return out;
  }

  static Future<String?> materializeUri(String uri, String name) async {
    try {
      final out = await _recordingsChannel.invokeMethod<String>(
        'materializeRecording',
        {'uri': uri, 'name': name.isEmpty ? 'audio.wav' : name},
      );
      if (out != null && out.isNotEmpty) return out;
    } catch (e) {
      debugPrint('[recordings] materializeUri failed: $e');
    }
    return null;
  }

  static Future<String> materializePath(Recording rec) async {
    final uri = rec.contentUri;
    if (uri != null && uri.isNotEmpty) {
      try {
        final name = rec.filePath.split(RegExp(r'[\\/]')).last;
        final out = await _recordingsChannel.invokeMethod<String>(
          'materializeRecording',
          {'uri': uri, 'name': name.isEmpty ? '${rec.id}.wav' : name},
        );
        if (out != null && out.isNotEmpty) return out;
      } catch (e) {
        debugPrint('[recordings] materialize failed: $e');
      }
    }
    return resolveFilePath(rec.filePath);
  }

  /// Task 116 П.2: удалить ВСЕ файлы записей (по contentUri или пути),
  /// БД и расшифровки НЕ трогаем. Для кнопки «Очистить» в настройках —
  /// подтверждение спрашивает вызывающий код.
  static Future<int> clearRecordingFiles(Box<Map> box) async {
    var removed = 0;
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      final rec = Recording.fromMap(Map<String, dynamic>.from(raw));
      try {
        if (rec.contentUri != null && rec.contentUri!.isNotEmpty) {
          await _recordingsChannel.invokeMethod<bool>(
              'deleteRecording', {'uri': rec.contentUri});
          removed++;
          continue;
        }
        final resolved = await resolveFilePath(rec.filePath);
        final f = File(resolved);
        if (await f.exists()) {
          await f.delete();
          removed++;
        }
      } catch (e) {
        debugPrint('[recordings] clear $key: $e');
      }
    }
    return removed;
  }

  /// Task 112: обратная совместимость — сначала ищем в новой папке, потом в старой.
  static Future<String> resolveFilePath(String stored) async {
    try {
      if (stored.isEmpty) return stored;
      if (await File(stored).exists()) return stored;
      // Task 116 (защита аудио): относительный вид 'Documents/...' —
      // переживает смену UUID контейнера на iOS.
      if (!Platform.isAndroid && stored.startsWith('Documents/')) {
        final docs = await getApplicationDocumentsDirectory();
        final candidate = File('${docs.path}/${stored}');
        if (await candidate.exists()) return candidate.path;
      }
      final name = stored.split(RegExp(r'[\\/]')).last;
      if (name.isEmpty) return stored;
      // Task 112: сначала ищем в новой папке DictaPro/Записи.
      final dir = await recordingsDir();
      final candidate = File('${dir.path}/$name');
      if (await candidate.exists()) return candidate.path;
      // Потом в старой app_flutter (миграция ещё не прошла).
      final docs = await getApplicationDocumentsDirectory();
      final legacy = File('${docs.path}/$name');
      if (await legacy.exists()) return legacy.path;
    } catch (_) {}
    return stored;
  }

  /// Task 112: миграция старых записей в новую папку.
  /// Task 116 П.2: на Android 10+ «новая папка» — публичная
  /// Documents/DictaPro/Записи через MediaStore (publishRecording).
  /// Файл остаётся на месте, если публикация не удалась. Вызывается при
  /// первом init. Старые файлы удаляются после успешной публикации.
  static Future<void> migrateRecordings(Box<Map> box) async {
    // Task 116 П.2: копии для чтения/проигрывания — временные, чистим при старте.
    try {
      final cacheDir = await getTemporaryDirectory();
      final mat = Directory('${cacheDir.path}/materialized');
      if (await mat.exists()) {
        await mat.delete(recursive: true);
      }
    } catch (_) {}

    try {
      final sdk = Platform.isAndroid ? await _androidSdk() : 0;
      var migrated = 0;

      // Task 116 (Славан): индекс «имя файла → путь» по всему Documents —
      // для записей, чей путь не удаётся восстановить через '/Documents/'.
      Map<String, String> docIndex = {};
      if (Platform.isIOS) {
        try {
          final docs = await getApplicationDocumentsDirectory();
          await for (final e
              in docs.list(recursive: true, followLinks: false)) {
            if (e is File) {
              final name = e.uri.pathSegments.last;
              docIndex.putIfAbsent(name, () => e.path);
            }
          }
        } catch (_) {}
      }

      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw == null) continue;
        final rec = Recording.fromMap(Map<String, dynamic>.from(raw));
        var oldPath = rec.filePath;
        if (oldPath.isEmpty) continue;
        var oldFile = File(oldPath);
        if (!await oldFile.exists() && Platform.isIOS) {
          // Task 116 (Славан): iOS при обновлении приложения меняет UUID
          // контейнера — абсолютные пути в базе ломаются, хотя файл на
          // месте (тот же относительный путь в новом контейнере).
          final marker = '/Documents/';
          final idx = oldPath.indexOf(marker);
          if (idx >= 0) {
            final docs =
                await getApplicationDocumentsDirectory();
            final candidate =
                docs.path + oldPath.substring(idx + marker.length - 1);
            if (await File(candidate).exists()) {
              oldPath = candidate;
              oldFile = File(candidate);
            }
          }
          // Глубокий поиск: у части старых записей путь был вообще без
          // '/Documents/' — ищем файл по имени по всему Documents.
          if (!await oldFile.exists()) {
            final name = oldPath.split(RegExp(r'[\\/]')).last;
            final hit = docIndex[name];
            if (hit != null) {
              oldPath = hit;
              oldFile = File(hit);
            }
          }
        }
        if (!await oldFile.exists()) continue;

        // Уже опубликован в публичной коллекции — путь указывает туда.
        if (rec.contentUri != null && rec.contentUri!.isNotEmpty) continue;

        if (sdk >= 29) {
          // Task 116 П.2: публикуем в Documents/DictaPro/Записи и убираем
          // приватную копию. Имена сохраняются.
          try {
            final name = oldPath.split(RegExp(r'[\\/]')).last;
            final pub = await _recordingsChannel.invokeMapMethod<String, dynamic>(
              'publishRecording',
              {'srcPath': oldPath, 'displayName': name},
            );
            if (pub != null && pub['path'] != null) {
              // Защита аудио: старый файл удаляем ТОЛЬКО если копия
              // существует и размер совпадает байт-в-байт.
              final newF = File(pub['path'] as String);
              final oldSize = await oldFile.length();
              if (await newF.exists() && await newF.length() == oldSize) {
                rec.filePath = pub['path'] as String;
                rec.contentUri = pub['uri'] as String?;
                await box.put(key, rec.toMap());
                try {
                  if (await oldFile.exists()) await oldFile.delete();
                } catch (_) {}
                migrated++;
              } else {
                debugPrint('[migrate] размер копии не совпал — '
                    'старый файл $oldPath сохранён');
              }
            }
          } catch (e) {
            debugPrint('[migrate] publish failed for $oldPath: $e');
          }
          continue;
        }

        // iOS / ≤API 28: локальная папка Documents/DictaPro/Записи.
        final newDir = await recordingsDir();
        if (oldPath.startsWith(newDir.path)) {
          // Защита аудио: путь уже в новой папке — сохраняем ОТНОСИТЕЛЬНО
          // (Documents/...), чтобы переживать смену UUID контейнера.
          final docs = await getApplicationDocumentsDirectory();
          if (Platform.isIOS && oldPath.startsWith(docs.path)) {
            final rel = oldPath.substring(docs.path.length + 1);
            if (rel != rec.filePath) {
              rec.filePath = rel;
              await box.put(key, rec.toMap());
            }
          }
          continue;
        }
        final name = oldPath.split(RegExp(r'[\\/]')).last;
        final newFile = File('${newDir.path}/$name');
        if (await newFile.exists()) {
          // Уже скопирован — обновляем путь; старый удаляем только
          // при совпадении размеров (защита аудио).
          final oldSize = await oldFile.length();
          final newSize = await newFile.length();
          rec.filePath = newFile.path;
          await box.put(key, rec.toMap());
          if (await oldFile.exists() &&
              oldPath != newFile.path &&
              oldSize == newSize) {
            await oldFile.delete();
          }
          migrated++;
          continue;
        }
        // Копируем.
        try {
          await oldFile.copy(newFile.path);
          // Защита аудио: удаление старого только при совпадении размеров.
          if (await newFile.length() == await oldFile.length()) {
            rec.filePath = newFile.path;
            await box.put(key, rec.toMap());
            await oldFile.delete();
          } else {
            debugPrint('[migrate] размер копии $name не совпал — '
                'старый файл сохранён');
          }
          migrated++;
        } catch (e) {
          debugPrint('[migrate] failed to copy $name: $e');
        }
      }
      if (migrated > 0) {
        debugPrint('[migrate] migrated $migrated recordings');
      }
    } catch (e) {
      debugPrint('[migrate] error: $e');
    }
  }

  Future<void> init() async {
    if (_isInit) return;

    await Permission.microphone.request();
    await Permission.storage.request();

    _box = await Hive.openBox<Map>('recordings');
    _isInit = true;

    // Task 112: миграция старых записей в новую папку.
    await migrateRecordings(_box!);

    // Task 116 (Славан): папка Документы/DictaPro/Записи должна быть видна
    // сразу после установки — создаём с файлом-подсказкой до первой записи.
    try {
      if (Platform.isAndroid) {
        await _recordingsChannel.invokeMethod('ensureRecordingsFolder');
      }
    } catch (_) {}
  }

  Future<String> startRecording() async {
    // Task 112: новая папка + понятное имя файла.
    final dir = await recordingsDir();
    final path = '${dir.path}/${_recordingFileName()}';

    // Читаем настройки из Hive
    int sampleRate = 16000;
    int numChannels = 1;
    try {
      final settingsBox = await Hive.openBox<dynamic>('settings');
      final raw = settingsBox.get('recorder');
      if (raw != null) {
        final settings = RecorderSettings.fromMap(Map<String, dynamic>.from(raw));
        sampleRate = settings.sampleRate;
        numChannels = settings.numChannels;
      }
    } catch (_) {
      // fallback к дефолтам
    }

    _startTime = DateTime.now();

    await _recorder.start(
      RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: sampleRate,
        numChannels: numChannels,
        // Сырой тракт без системного шумодава/AGC: VOICE_RECOGNITION по CDD
        // обязан отключать DSP. Исследование: системная обработка ухудшает ASR.
        androidConfig: const AndroidRecordConfig(
          audioSource: AndroidAudioSource.voiceRecognition,
        ),
      ),
      path: path,
    );

    await _startKeepAliveService();

    return path;
  }

  /// Живой уровень сигнала при записи: 0..1 (для индикатора на экране).
  /// record 5.x отдаёт амплитуду в dBFS: -60 (тишина) .. 0 (максимум).
  Stream<double> amplitudeLevel(
      {Duration interval = const Duration(milliseconds: 80)}) {
    return _recorder.onAmplitudeChanged(interval).map((amp) {
      final db = amp.current.isFinite ? amp.current : -60.0;
      final norm = ((db + 60.0) / 60.0).clamp(0.0, 1.0);
      // небольшая кривая: речь обычно -25..-12 dBFS, так полоса живее
      return math.pow(norm, 0.7).toDouble();
    });
  }

  void setSleepTimer(int minutes, Function onComplete) {
    _sleepTimer?.cancel();
    _sleepDurationMinutes = minutes;
    _sleepTimer = Timer(Duration(minutes: minutes), () {
      stopRecording().then((_) => onComplete());
    });
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepDurationMinutes = null;
  }

  int? get sleepDurationMinutes => _sleepDurationMinutes;

  String _generateDefaultTitle(DateTime dt) {
    final d = '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}';
    final t = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return AppStrings.tfGlobal('default_title_recording', {'d': d, 't': t});
  }

  Future<void> _startKeepAliveService() async {
    try {
      if (await FlutterForegroundTask.isRunningService) return;
      final perm = await FlutterForegroundTask.checkNotificationPermission();
      if (perm != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      await FlutterForegroundTask.startService(
        notificationTitle: AppStrings.tGlobal('notif_recording_title'),
        notificationText: AppStrings.tGlobal('notif_recording_text'),
        // Task 116 П.7: тап по уведомлению записи возвращает в приложение
        // без пересоздания процесса (singleTask + launchApp).
        callback: dictaTaskCallback,
      );
    } catch (_) {
      // не критично: запись продолжается, пока приложение активно
    }
  }

  Future<void> _stopKeepAliveService() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {}
  }

  Future<dynamic> stopRecording() async {
    await _stopKeepAliveService();
    final path = await _recorder.stop();

    // Task 099: record-плагин на iOS не всегда финализирует WAV-заголовок
    // при прерывании/остановке (data size=0) — чиним постфактум, пока
    // файл не ушёл в плейер/конвертер/отправку.
    if (path != null) await WavHeaderFixer.fix(path);

    final duration = _startTime != null
        ? DateTime.now().difference(_startTime!)
        : Duration.zero;
    _startTime = null;

    final file = File(path!);
    final size = await file.length();
    final now = DateTime.now();

    // Task 116 П.2: публикуем запись в публичную Documents/DictaPro/Записи
    // (MediaStore). Пользователю — понятный путь и файл-менеджер; записи
    // не прячутся в Android/data/<pkg>/files. Исходный temp-файл из
    // app-private после публикации удаляем. На iOS/≤API 28 — как раньше.
    String finalPath = path;
    String? contentUri;
    try {
      if (Platform.isAndroid && await _androidSdk() >= 29) {
        final name = path.split(RegExp(r'[\\/]')).last;
        final pub = await _recordingsChannel.invokeMapMethod<String, dynamic>(
          'publishRecording',
          {'srcPath': path, 'displayName': name},
        );
        if (pub != null && pub['path'] != null) {
          finalPath = pub['path'] as String;
          contentUri = pub['uri'] as String?;
          try {
            if (await file.exists()) await file.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      // Публикация не удалась (редко) — оставляем файл в app-private,
      // запись всё равно работает, при следующем старте миграция довезёт.
      debugPrint('[recordings] publish failed: $e');
    }

    final recording = Recording(
      id: now.millisecondsSinceEpoch.toString(),
      filePath: finalPath,
      createdAt: now,
      durationMs: duration.inMilliseconds,
      fileSize: size,
      title: _generateDefaultTitle(now),
      contentUri: contentUri,
    );

    await _box!.put(recording.id, recording.toMap());
    return recording;
  }

  Future<void> playRecording(String path) async {
    await _player.stop();
    await _player.setFilePath(path);
    await _player.play();
  }

  Future<void> stopPlaying() async {
    await _player.stop();
  }

  /// Task 116 П.2: доступ к box записей для операций вне сервиса
  /// (например, «Очистить» в настройках). Открывает если ещё не открыт.
  static Future<Box<Map>> openRecordingsBox() async {
    final existing = _instance._box;
    if (existing != null && existing.isOpen) return existing;
    final box = await Hive.openBox<Map>('recordings');
    _instance._box = box;
    return box;
  }

  Future<void> deleteRecording(String id) async {
    final map = _box!.get(id);
    if (map != null) {
      // Task 116 П.2: файл может жить в публичной коллекции — удаляем
      // через MediaStore по contentUri (свой файл, разрешения не нужны).
      final uri = map['contentUri'] as String?;
      if (uri != null && uri.isNotEmpty) {
        try {
          await _recordingsChannel
              .invokeMethod<bool>('deleteRecording', {'uri': uri});
        } catch (_) {}
      }
      final file = File(map['filePath'] as String);
      if (await file.exists()) await file.delete();
      await _box!.delete(id);
    }
  }

  /// Task 059: достать запись по id (сохранение онлайн-итогов обратно).
  Recording? getRecordingById(String id) {
    final box = _box;
    if (box == null) return null;
    final raw = box.get(id);
    if (raw == null) return null;
    final map = Map<String, dynamic>.from(raw as Map);
    map['id'] = id;
    return Recording.fromMap(map);
  }

  Future<void> updateRecording(Recording recording) async {
    await _box!.put(recording.id, recording.toMap());
  }

  List<Recording> getAllRecordings() {
    final maps = _box!.values.toList();
    maps.sort(
        (a, b) => (b['createdAt'] as int).compareTo(a['createdAt'] as int));
    return maps
        .map((m) => Recording.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  void dispose() {
    _sleepTimer?.cancel();
    _recorder.dispose();
    _player.dispose();
  }
}
