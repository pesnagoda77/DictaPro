// GigaAM v3 (sherpa_onnx) — единственный офлайн-движок распознавания (task 019).
// Модель ВЛОЖЕНА в сборку: никаких сетевых загрузок и экранов докачивания.
//   • AAB (Play): install-time asset pack "gigaam_pack" (≤1,5 ГБ, ставится
//     одной операцией с приложением). Путь отдаёт нативная прослойка
//     MainActivity.kt через MethodChannel 'dictapro/model'.
//   • APK (прямая раздача): те же файлы копируются tools/prepare_apk_build.py
//     в flutter-ассеты assets/models/gigaam_v3_punct/ и при первом запуске
//     копируются во внутреннее хранилище (локально, без сети).
// Перед сборкой модель скачивается tools/fetch_model.py →
// android/gigaam_pack/src/main/assets/models/gigaam_v3_punct/.
// Исследование: docs/research/Исследование_Whisper_GigaAM_2026.md.
// Качество (модель/нарезка/VAD) заморожено — см. git-историю, не менять.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'glossary_service.dart';

class GigaamService {
  /// Файлы модели GigaAM v3 + Silero VAD.
  static const modelFiles = [
    'encoder.int8.onnx',
    'decoder.onnx',
    'joiner.onnx',
    'tokens.txt',
    'silero_vad.onnx',
  ];

  static const _channel = MethodChannel('dictapro/model');

  /// Маркер завершённой подготовки (в пределах сессии).
  static bool _prepared = false;

  /// true — модель уже в рабочей директории (или подготовка идёт/завершена).
  /// Используется UI, чтобы показать «Подготовка модели» только при первом
  /// запуске, а не перед каждой транскрибацией.
  static bool get isPrepared => _prepared;

  /// Директория рабочей копии модели во внутреннем хранилище.
  /// Файлы сюда попадают из asset pack (AAB, Play) или копируются
  /// из flutter-ассетов (APK) — движку нужны обычные файловые пути.
  static Future<Directory> modelDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/models/gigaam_v3_punct');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Гарантирует, что все файлы модели лежат в [modelDir].
  /// Вызывать перед каждой транскрибацией — повторный вызов бесплатен.
  /// [onProgress] — (скопировано байт, всего байт) для экрана
  /// «Подготовка модели» при первом запуске (копирование локальное,
  /// без сети, отмены нет — модель обязана оказаться на месте).
  /// Бросает исключение, если модель недоступна (не подложили в сборку).
  static Future<void> ensureModelReady({
    void Function(int copied, int total)? onProgress,
  }) async {
    if (_prepared) return;
    final dir = await modelDir();
    if (_allPresent(dir)) {
      _prepared = true;
      return;
    }

    // 1) Play install-time asset pack (AAB): обычные файлы — копируем
    //    потоково с точным прогрессом по байтам.
    final packDir = await _assetPackDir();
    if (packDir != null) {
      final src = Directory('$packDir/models/gigaam_v3_punct');
      if (_allPresent(src)) {
        await _copyFrom(src, dir, onProgress);
        _prepared = true;
        debugPrint('[gigaam] model prepared from asset pack');
        return;
      }
    }

    // 2) Flutter assets (APK, прямая раздача): bundle читается целиком
    //    в память, поэтому прогресс по файлам (порция = total/5).
    try {
      const approxTotal = 244 * 1024 * 1024; // ~222 МБ модель + запас
      var doneFiles = 0;
      for (final f in modelFiles) {
        final data = await rootBundle.load('assets/models/gigaam_v3_punct/$f');
        final bytes = data.buffer.asUint8List();
        final out = File('${dir.path}/$f');
        await out.writeAsBytes(bytes, flush: true);
        doneFiles++;
        onProgress?.call(
          (approxTotal * doneFiles / modelFiles.length).round(),
          approxTotal,
        );
      }
      if (_allPresent(dir)) {
        _prepared = true;
        debugPrint('[gigaam] model prepared from bundle assets');
        return;
      }
    } catch (e) {
      debugPrint('[gigaam] bundle assets unavailable: $e');
    }

    throw StateError(
      'Модель распознавания не найдена в сборке. '
      'Перед сборкой запустите tools/fetch_model.py (см. docs/СБОРКА.md).',
    );
  }

  /// Потоковое копирование модели из [src] в [dst] с точным прогрессом.
  static Future<void> _copyFrom(
    Directory src,
    Directory dst,
    void Function(int copied, int total)? onProgress,
  ) async {
    var total = 0;
    for (final f in modelFiles) {
      total += File('${src.path}/$f').lengthSync();
    }
    var copied = 0;
    for (final f in modelFiles) {
      final s = File('${src.path}/$f');
      final d = File('${dst.path}/$f');
      final expected = s.lengthSync();
      if (d.existsSync() && d.lengthSync() == expected) {
        copied += expected;
        onProgress?.call(copied, total);
        continue;
      }
      final reader = s.openRead();
      final writer = d.openWrite();
      try {
        await for (final chunk in reader) {
          writer.add(chunk);
          copied += chunk.length;
          onProgress?.call(copied, total);
        }
      } finally {
        await writer.close();
      }
      if (d.lengthSync() != expected) {
        throw StateError('Ошибка копирования модели: $f');
      }
    }
  }

  static bool _allPresent(Directory d) {
    for (final f in modelFiles) {
      final file = File('${d.path}/$f');
      if (!file.existsSync() || file.lengthSync() == 0) return false;
    }
    return true;
  }

  /// Путь к директории файлов asset pack из нативной прослойки.
  /// null — пак недоступен (APK-раздача или ошибка).
  static Future<String?> _assetPackDir() async {
    try {
      final path = await _channel.invokeMethod<String>('getGigaamModelPath');
      if (path == null || path.isEmpty) return null;
      final d = Directory(path);
      return d.existsSync() ? path : null;
    } catch (_) {
      return null;
    }
  }

  // ---------- Распознавание ----------

  /// Транскрибирует WAV (моно 16 кГц) через GigaAM v3.
  /// Нарезка по паузам Silero VAD, декодирование в отдельном изоляте.
  /// Прогресс: onProgress(фрагмент i, всего N).
  /// [skipChunks] — сколько первых кусков НЕ расшифровывать (task 036):
  /// их текст уже сохранён в partial.txt от прерванного прогона, нарезка
  /// VAD детерминирована, поэтому порядковые номера кусков совпадают.
  static Future<String?> transcribe(
    String wavPath, {
    int skipChunks = 0,
    void Function(int done, int total)? onProgress,
    void Function(int done, int total, String text)? onPartial,
    void Function(String line)? onLog,
  }) async {
    await ensureModelReady();
    final dir = (await modelDir()).path;
    final receivePort = ReceivePort();
    late Isolate isolate;
    isolate = await Isolate.spawn<_GigaamJob>(
      _gigaamIsolateEntry,
      _GigaamJob(
        modelDir: dir,
        wavPath: wavPath,
        skipChunks: skipChunks,
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
          case 'partial':
            // Задача 036: промежуточный текст — чтобы результат не терялся.
            onPartial?.call(message[1] as int, message[2] as int,
                message[3] as String);
          case 'log':
            debugPrint('[gigaam] ${message[1]}');
            onLog?.call('${message[1]}');
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

  /// Транскрибация GigaAM + глоссарий терминов.
  ///
  /// Важно: текстовая чистка из задачи 016 (числительные→цифры, пунктуация)
  /// рассчитана на VOSK, который выдаёт строчную кашу без знаков. GigaAM сам
  /// даёт пунктуацию, регистр и числа, поэтому чистка ему не нужна: на замерах
  /// 16.09 она добавляла 2-4 п.п. ошибок и артефакты вида «на$1..в».
  /// Оставляем только глоссарий «Термины записи» (HotwordsStorage):
  /// пользовательские термины (в т.ч. латиница/аббревиатуры), которые модель
  /// не может выдать сама. Без списка текст не меняется.
  static Future<String?> transcribeWithGlossary(
    String wavPath, {
    int skipChunks = 0,
    void Function(int done, int total)? onProgress,
    void Function(int done, int total, String text)? onPartial,
    void Function(String line)? onLog,
  }) async {
    final text = await transcribe(wavPath,
        skipChunks: skipChunks,
        onProgress: onProgress,
        onPartial: onPartial,
        onLog: onLog);
    if (text == null) return null;
    var out = text;
    final terms = await HotwordsStorage.recent();
    if (terms.isNotEmpty) {
      out = GlossaryService.apply(out, terms);
    }
    return out;
  }
}

class _GigaamJob {
  final String modelDir;
  final String wavPath;
  final int skipChunks;
  final SendPort progressPort;
  const _GigaamJob({
    required this.modelDir,
    required this.wavPath,
    this.skipChunks = 0,
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
          minSilenceDuration: 0.8,
          maxSpeechDuration: 20.0,
          windowSize: 512,
        ),
        sampleRate: 16000,
        // Task 045: было numThreads: 1 → 4. VAD (нарезка) при 1 потоке
        // узкое место на длинных файлах; замер на реальной записи —
        // фаза нарезки ускоряется заметно, декодер и так на 4 потоках.
        numThreads: 4,
      ),
      bufferSizeInSeconds: 60,
    );

    final parts = <String>[];
    var idx = 0;
    var vadSegs = 0;
    var planned = 0; // сколько всего кусков пойдёт в декодер (для прогресса)
    final segLens = <int>[];

    // Замерено на реальной записи (локальный прогон): лучшая конфигурация —
    // паузы ≥0.8 с и кусок до 20 с (WER 18.9%). Модель держит и 60 с без вылета,
    // 20 с — безопасный запас. Перехлёст со склейкой ПРОВЕРЕН и ОТКЛЮЧЁН
    // (добавлял лишние слова). Режем только через поиск паузы.
    const maxSegSamples = 320000; // 20 с
    const minSegSamples = 160000; // не режем раньше 10 с
    const searchSamples = 24000; // 1.5 с — окно поиска паузы

    // Самая тихая точка в окне [from, to) — там резать безопаснее всего.
    int findQuiet(Float32List a, int from, int to) {
      var f = from < 0 ? 0 : from;
      var t = to > a.length ? a.length : to;
      const step = 160; // 10 мс
      var bestIdx = t;
      var bestE = double.infinity;
      for (var s = f; s + step <= t; s += step) {
        var acc = 0.0;
        for (var k = s; k < s + step; k++) {
          acc += a[k].abs();
        }
        if (acc < bestE) {
          bestE = acc;
          bestIdx = s;
        }
      }
      return bestIdx;
    }

    void decodeOne(Float32List raw) {
      // Пустые/микроскопические куски в декодер не отдаём (роняют нативный ORT).
      if (raw.length < 1600) return; // < 0.1 с
      idx++; // абсолютный номер куска (с учётом пропущенных) — для прогресса
      job.progressPort.send(['progress', idx, planned]);
      // Task 036: куски до skipChunks уже расшифрованы в прошлом прогоне —
      // их текст лежит в partial.txt, декодировать повторно не нужно.
      if (idx <= job.skipChunks) return;
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
        if (idx % 5 == 0) {
          // Задача 036: каждые 5 кусков отдаём накопленный текст наружу,
          // чтобы он сохранился на диск в обход изолята.
          job.progressPort.send(['partial', idx, planned, parts.join(' ')]);
        }
      } finally {
        stream.free();
      }
    }

    void decodeSegment(Float32List raw) {
      if (raw.length <= maxSegSamples) {
        decodeOne(raw);
        return;
      }
      var start = 0;
      while (start < raw.length) {
        var end = start + maxSegSamples;
        if (end >= raw.length) {
          decodeOne(Float32List.sublistView(raw, start, raw.length));
          break;
        }
        final winFrom = (end - searchSamples) > (start + minSegSamples)
            ? (end - searchSamples)
            : (start + minSegSamples);
        final q = findQuiet(raw, winFrom, end);
        if (q > start + minSegSamples && q < end) end = q;
        decodeOne(Float32List.sublistView(raw, start, end));
        start = end;
      }
    }

    final wave = sherpa.readWave(job.wavPath);
    final samples = wave.samples;
    final total = samples.length;
    job.progressPort.send([
      'log',
      'start: rate=${wave.sampleRate} samples=$total (${(total / 16000).toStringAsFixed(1)} c) '
          'silence>=0.8 c, max=20 c'
    ]);

    // Как на эталонном прогоне: кормим по 512 сэмплов (32 мс), буфер 60 с.
    // Фаза 1 — нарезка (быстрая): собираем куски, чтобы потом показать честный прогресс.
    final segs = <Float32List>[];
    const chunk = 512;
    var offset = 0;
    while (offset < total) {
      final end = (offset + chunk > total) ? total : offset + chunk;
      vad.acceptWaveform(Float32List.sublistView(samples, offset, end));
      offset = end;
      while (!vad.isEmpty()) {
        vadSegs++;
        segLens.add(vad.front().samples.length);
        segs.add(Float32List.fromList(vad.front().samples));
        vad.pop();
      }
    }
    vad.flush();
    while (!vad.isEmpty()) {
      vadSegs++;
      segLens.add(vad.front().samples.length);
      segs.add(Float32List.fromList(vad.front().samples));
      vad.pop();
    }

    // Фаза 2 — расшифровка. Число проходов известно заранее: показываем «кусок X из N».
    for (final s in segs) {
      planned += (s.length <= maxSegSamples)
          ? 1
          : ((s.length + maxSegSamples - 1) ~/ maxSegSamples);
    }
    var speechSamples = 0;
    for (final s in segs) {
      speechSamples += s.length;
    }
    job.progressPort.send([
      'log',
      'покрытие: wav=${(total / 16000).toStringAsFixed(1)} c, речь=${(speechSamples / 16000).toStringAsFixed(1)} c '
          '(${(100 * speechSamples / total).toStringAsFixed(1)}% от файла), кусков=$vadSegs, planned=$planned'
    ]);
    for (final s in segs) {
      decodeSegment(s);
    }

    job.progressPort.send([
      'log',
      'vad segments=$vadSegs decoded=$idx parts=${parts.length} '
          'lens=${segLens.take(40).join(',')}'
    ]);

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
