import 'dart:async';
import 'dart:io';
import 'package:record/record.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hive/hive.dart';

import 'models/transcription.dart';
import 'settings_page.dart';

export 'models/transcription.dart' show DialogueSegment;

class Recording {
  String id;
  String filePath;
  DateTime createdAt;
  int durationMs;
  int fileSize;
  String? title;
  String? transcription;
  List<Map<String, dynamic>>? segments;
  bool isFavorite;

  List<String>? tags;
  String? summary;
  List<String>? decisions;
  List<Map<String, dynamic>>? speakerStats;

  Recording({
    required this.id,
    required this.filePath,
    required this.createdAt,
    required this.durationMs,
    required this.fileSize,
    this.title,
    this.transcription,
    this.segments,
    this.isFavorite = false,
    this.tags,
    this.summary,
    this.decisions,
    this.speakerStats,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'filePath': filePath,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'durationMs': durationMs,
        'fileSize': fileSize,
        'title': title,
        'transcription': transcription,
        'segments': segments,
        'isFavorite': isFavorite,
        'tags': tags,
        'summary': summary,
        'decisions': decisions,
        'speakerStats': speakerStats?.map((s) => s.map((k, v) => MapEntry(k, v.toString()))).toList(),
      };

  factory Recording.fromMap(Map<String, dynamic> map) => Recording(
        id: map['id'] as String,
        filePath: map['filePath'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
        durationMs: map['durationMs'] as int,
        fileSize: map['fileSize'] as int,
        title: map['title'] as String?,
        transcription: map['transcription'] as String?,
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
        decisions: map['decisions'] != null
            ? (map['decisions'] as List).cast<String>()
            : null,
        speakerStats: map['speakerStats'] != null
            ? (map['speakerStats'] as List)
                .map((item) => (item as Map).map((k, v) => MapEntry<String, dynamic>(k as String, v)))
                .toList()
            : null,
      );
}

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
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

  Future<void> init() async {
    if (_isInit) return;

    await Permission.microphone.request();
    await Permission.storage.request();

    _box = await Hive.openBox<Map>('recordings');
    _isInit = true;
  }

  Future<String> startRecording() async {
    final dir = await getApplicationDocumentsDirectory();
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final path = '${dir.path}/recording_$id.wav';

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
    final day = dt.day;
    const monthNames = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
    ];
    final month = monthNames[dt.month - 1];
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return 'Запись $day $month, $hour:$minute';
  }

  Future<void> _startKeepAliveService() async {
    try {
      if (await FlutterForegroundTask.isRunningService) return;
      final perm = await FlutterForegroundTask.checkNotificationPermission();
      if (perm != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      await FlutterForegroundTask.startService(
        notificationTitle: 'DictaPro — идёт запись',
        notificationText: 'Запись продолжается при выключенном экране',
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

    final duration = _startTime != null
        ? DateTime.now().difference(_startTime!)
        : Duration.zero;
    _startTime = null;

    final file = File(path!);
    final size = await file.length();
    final now = DateTime.now();

    final recording = Recording(
      id: now.millisecondsSinceEpoch.toString(),
      filePath: path,
      createdAt: now,
      durationMs: duration.inMilliseconds,
      fileSize: size,
      title: _generateDefaultTitle(now),
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

  Future<void> deleteRecording(String id) async {
    final map = _box!.get(id);
    if (map != null) {
      final file = File(map['filePath'] as String);
      if (await file.exists()) await file.delete();
      await _box!.delete(id);
    }
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
