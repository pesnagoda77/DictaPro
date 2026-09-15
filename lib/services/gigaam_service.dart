// GigaAM v3 (sherpa_onnx) — второй офлайн-движок распознавания.
// Исследование: docs/research/Исследование_Whisper_GigaAM_2026.md (разделы 2.1, 3.4, 4).
// Модель: GigaAM v3 RNN-T e2e с пунктуацией (csukuangfj/sherpa-onnx-nemo-transducer-punct-giga-am-v3-russian-2025-12-16)
// + фолбэк GigaAM v2 (официальный список sherpa-onnx).
// Всё локально: сеть только для скачивания модели по явному действию пользователя.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'local_text_cleanup.dart';

class GigaamService {
  static const _engineKey = 'asr_engine'; // vosk | gigaam

  // GigaAM v3 e2e (с пунктуацией) — основной набор
  static const v3Base =
      'https://huggingface.co/csukuangfj/sherpa-onnx-nemo-transducer-punct-giga-am-v3-russian-2025-12-16/resolve/main';
  static const v3Files = [
    'encoder.int8.onnx',
    'decoder.onnx',
    'joiner.onnx',
    'tokens.txt',
  ];

  // Silero VAD (нужен для нарезки по паузам, ~2 МБ)
  static const vadUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx';

  /// Директория моделей: getApplicationSupportDirectory()/models/gigaam_v3
  static Future<Directory> modelDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/models/gigaam_v3');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  // ---------- Движок ----------

  static Future<String> getEngine() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_engineKey) ?? 'vosk';
  }

  static Future<void> setEngine(String engine) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_engineKey, engine);
  }

  // ---------- Статус модели ----------

  static Future<bool> isModelDownloaded() async {
    final dir = await modelDir();
    for (final f in v3Files) {
      if (!File('${dir.path}/$f').existsSync()) return false;
    }
    return true;
  }

  static Future<int> modelSizeBytes() async {
    final dir = await modelDir();
    var total = 0;
    for (final f in v3Files) {
      final file = File('${dir.path}/$f');
      if (file.existsSync()) total += file.lengthSync();
    }
    return total;
  }

  // ---------- Скачивание ----------

  /// Скачивает набор v3 + silero_vad.onnx с докачкой (HTTP Range).
  /// [onProgress] — (скачано байт всего, всего байт, текущий файл).
  static Future<bool> downloadModel(
    void Function(int received, int total, String file) onProgress,
  ) async {
    final dir = await modelDir();
    final totalBytes = 225 * 1024 * 1024 + 8 * 1024 * 1024; // грубая оценка v3 + vad
    var received = 0;

    final jobs = <(String, String)>[
      for (final f in v3Files) ('$v3Base/$f', f),
      (vadUrl, 'silero_vad.onnx'),
    ];

    for (final (url, name) in jobs) {
      final file = File('${dir.path}/$name');
      var start = 0;
      if (file.existsSync()) start = file.lengthSync();

      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(url));
        if (start > 0) request.headers.add('Range', 'bytes=$start-');
        final response = await request.close();

        if (response.statusCode == 416) {
          // Файл уже скачан полностью (Range за концом файла) — пропускаем,
          // а не показываем «ошибку сети».
          await response.drain();
          onProgress(received, totalBytes, name);
          continue;
        }
        if (response.statusCode == 200 && start > 0) {
          // сервер не поддержал Range — качаем заново
          await file.delete();
          start = 0;
        } else if (response.statusCode != 200 && response.statusCode != 206) {
          debugPrint('[gigaam] download $name failed: ${response.statusCode}');
          return false;
        }

        final sink = file.openWrite(
            mode: start > 0 ? FileMode.append : FileMode.write);
        var lastPing = DateTime.now();
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          // прогресс не чаще ~5 раз/сек, чтобы не устраивать шторм setState
          final now = DateTime.now();
          if (now.difference(lastPing).inMilliseconds >= 200) {
            lastPing = now;
            onProgress(received, totalBytes, name);
          }
        }
        await sink.close();
        onProgress(received, totalBytes, name);
      } finally {
        client.close();
      }
    }
    return isModelDownloaded();
  }

  // ---------- Распознавание ----------

  /// Транскрибирует WAV (моно 16 кГц) через GigaAM v3.
  /// Нарезка по паузам Silero VAD, декодирование в отдельном изоляте.
  /// Прогресс: onProgress(фрагмент i, всего N).
  static Future<String?> transcribe(
    String wavPath, {
    void Function(int done, int total)? onProgress,
  }) async {
    final dir = (await modelDir()).path;
    final vadFile = '$dir/silero_vad.onnx';
    if (!File(vadFile).existsSync()) {
      debugPrint('[gigaam] silero_vad.onnx missing');
      return null;
    }

    final receivePort = ReceivePort();
    late Isolate isolate;
    isolate = await Isolate.spawn<_GigaamJob>(
      _gigaamIsolateEntry,
      _GigaamJob(
        modelDir: dir,
        wavPath: wavPath,
        progressPort: receivePort.sendPort,
      ),
      debugName: 'gigaam-asr',
    );

    final completer = Completer<String?>();
    receivePort.listen((message) {
      if (message is List) {
        switch (message[0] as String) {
          case 'progress':
            onProgress?.call(message[1] as int, message[2] as int);
          case 'done':
            completer.complete(message[1] as String?);
            receivePort.close();
            isolate.kill();
          case 'error':
            debugPrint('[gigaam] isolate error: ${message[1]}');
            completer.complete(null);
            receivePort.close();
            isolate.kill();
        }
      }
    });
    return completer.future;
  }

  /// Транскрибация с локальной чисткой 016 (по настройке).
  static Future<String?> transcribeWithCleanup(
    String wavPath, {
    void Function(int done, int total)? onProgress,
  }) async {
    final text = await transcribe(wavPath, onProgress: onProgress);
    if (text == null) return null;
    if (await LocalTextCleanupSettings.isEnabled()) {
      return LocalTextCleanup.cleanup(text);
    }
    return text;
  }
}

class _GigaamJob {
  final String modelDir;
  final String wavPath;
  final SendPort progressPort;
  const _GigaamJob({
    required this.modelDir,
    required this.wavPath,
    required this.progressPort,
  });
}

/// Точка входа изолята: FFI-объекты создаём ЗДЕСЬ (нативные указатели
/// между изолятами не передаются). initBindings — синхронно, .so уже
/// в нативной директории приложения.
void _gigaamIsolateEntry(_GigaamJob job) {
  sherpa.OfflineRecognizer? recognizer;
  sherpa.VoiceActivityDetector? vad;
  try {
    sherpa.initBindings();

    // --- Распознаватель GigaAM v3 (nemo_transducer) ---
    recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        // GigaAM использует 64-мерные log-mel признаки. Дефолт sherpa_onnx — 80,
        // с ним модель выдаёт мусор (см. issue k2-fsa/sherpa-onnx#3619).
        feat: const sherpa.FeatureConfig(sampleRate: 16000, featureDim: 64),
        model: sherpa.OfflineModelConfig(
          transducer: sherpa.OfflineTransducerModelConfig(
            encoder: '${job.modelDir}/encoder.int8.onnx',
            decoder: '${job.modelDir}/decoder.onnx',
            joiner: '${job.modelDir}/joiner.onnx',
          ),
          tokens: '${job.modelDir}/tokens.txt',
          modelType: 'nemo_transducer',
          numThreads: 4,
          debug: false,
        ),
      ),
    );

    // --- VAD: режем по паузам и СРАЗУ расшифровываем (без накопления сегментов) ---
    vad = sherpa.VoiceActivityDetector(
      config: sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(
          model: '${job.modelDir}/silero_vad.onnx',
          threshold: 0.5,
          minSpeechDuration: 0.25,
          minSilenceDuration: 0.5,
          maxSpeechDuration: 15.0,
          windowSize: 512,
        ),
        sampleRate: 16000,
        numThreads: 1,
      ),
      bufferSizeInSeconds: 30,
    );

    final parts = <String>[];
    var idx = 0;

    // GigaAM (int8) падает в нативном ORT, если кусок длиннее возможностей
    // модели (Mul в self_attn: broadcast-несовместимость, 5000 by 16626).
    // Режем САМИ, не надеясь на лимит VAD: максимум 10 с на один проход декодера.
    const maxSegSamples = 160000; // 10 с * 16 кГц

    void decodeOne(Float32List raw) {
      // Пустые/микроскопические куски в декодер не отдаём (роняют нативный ORT).
      if (raw.length < 1600) return; // < 0.1 с
      idx++;
      job.progressPort.send(['progress', idx, 0]);
      final stream = recognizer!.createStream();
      try {
        // Копия в обычный буфер: оригинал может быть вью на внутренний
        // буфер VAD и стать невалидным после pop().
        stream.acceptWaveform(
          samples: Float32List.fromList(raw),
          sampleRate: 16000,
        );
        recognizer.decode(stream);
        final text = recognizer.getResult(stream).text.trim();
        if (text.isNotEmpty) parts.add(text);
      } finally {
        stream.free();
      }
    }

    void decodeSegment(Float32List raw) {
      if (raw.length <= maxSegSamples) {
        decodeOne(raw);
        return;
      }
      for (var s = 0; s < raw.length; s += maxSegSamples) {
        final e =
            (s + maxSegSamples > raw.length) ? raw.length : s + maxSegSamples;
        decodeOne(Float32List.sublistView(raw, s, e));
      }
    }

    final wave = sherpa.readWave(job.wavPath);
    final samples = wave.samples;
    final total = samples.length;

    const chunk = 51200; // ~3.2 с за раз
    var offset = 0;
    while (offset < total) {
      final end = (offset + chunk > total) ? total : offset + chunk;
      vad.acceptWaveform(Float32List.sublistView(samples, offset, end));
      offset = end;
      while (!vad.isEmpty()) {
        decodeSegment(vad.front().samples);
        vad.pop();
      }
    }
    vad.flush();
    while (!vad.isEmpty()) {
      decodeSegment(vad.front().samples);
      vad.pop();
    }

    job.progressPort.send(['done', parts.join(' ')]);
  } catch (e) {
    job.progressPort.send(['error', e.toString()]);
  } finally {
    try {
      vad?.free();
    } catch (_) {}
    try {
      recognizer?.free();
    } catch (_) {}
  }
}
