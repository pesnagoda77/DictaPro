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
// Задача 078: манифест целостности (ModelManifest) — валидация размеров+
// sha256 ДО загрузки движка; самопочинка рабочей копии; без крашей.
// Сохранено с линии task-068: whisper (ensureWhisperReady) и fast-follow
// (_waitForPack/phase, task 067).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'keep_alive.dart';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'glossary_service.dart';

/// Задача 078: манифест целостности моделей.
/// Эталон снят 03.10 с файлов fast-follow пакета
/// (android/gigaam_pack/src/main/assets/models/...). Файлы моделей
/// НЕ менять (качество заморожено); при обновлении модели обновить манифест
/// и поднять [ModelManifest.version].
abstract final class ModelManifest {
  /// Версия манифеста. Пишется в маркер verified.json; смена версии
  /// инвалидирует старые маркеры и заставляет прогнать полную проверку.
  static const version = 1;

  static const gigaamPrefix = 'gigaam_v3_punct';
  static const whisperPrefix = 'whisper-small';

  /// Эталонные размеры + sha256. Формат: путь относительно models/,
  /// размер в байтах, sha256 (hex, регистр не важен).
  static const items = [
    ModelFileSpec(
      'gigaam_v3_punct/encoder.int8.onnx',
      224570820,
      '369f35a71bf288d3b8e0391fabd8dba5f2314088d440bca474056b7b4b6e66bf',
    ),
    ModelFileSpec(
      'gigaam_v3_punct/decoder.onnx',
      4600132,
      '38fc7475443ea2a26f63211ca350f73ac50fff824ab7a3876ee2bd610c53bbc4',
    ),
    ModelFileSpec(
      'gigaam_v3_punct/joiner.onnx',
      2712896,
      '602ff7017a93311aad34df1437c8d7f49911353c13d6eae7a6ee7b041339465c',
    ),
    ModelFileSpec(
      'gigaam_v3_punct/tokens.txt',
      13354,
      '39abae20e692998290c574e606f11a9edef2902a1995463fcff63d1490cf22b7',
    ),
    ModelFileSpec(
      'gigaam_v3_punct/silero_vad.onnx',
      643854,
      '9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6',
    ),
    ModelFileSpec(
      'whisper-small/small-encoder.int8.onnx',
      112442483,
      '4cbe7b22fa9026b843b60a68640c747de05bafb1a11b57edc0e66c232d9f33a9',
    ),
    ModelFileSpec(
      'whisper-small/small-decoder.int8.onnx',
      262226114,
      'acad50b5c782696e91b55914cc5ab4f756f1532f76e22aa6fc615f39fb69a8ee',
    ),
    ModelFileSpec(
      'whisper-small/small-tokens.txt',
      866987,
      'febeed8e568f92d9ca984580bc2e6b605b867dc5ba4486f9646de381b44a8226',
    ),
  ];

  static List<ModelFileSpec> forPrefix(String prefix) => items
      .where((e) => e.relPath.startsWith('$prefix/'))
      .toList(growable: false);
}

class ModelFileSpec {
  final String relPath;
  final int size;
  final String sha256;
  const ModelFileSpec(this.relPath, this.size, this.sha256);

  /// Имя файла без директории (рабочая копия лежит плоско в modelDir).
  String get basename => relPath.split('/').last;
}

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

  /// Файлы мультиязычной модели Whisper (EN/DE/…), int8 — одна на все языки.
  static const whisperFiles = [
    'small-encoder.int8.onnx',
    'small-decoder.int8.onnx',
    'small-tokens.txt',
  ];

  /// Маркер завершённой подготовки (в пределах сессии).
  static bool _prepared = false;

  /// true — модель уже в рабочей директории (или подготовка идёт/завершена).
  /// Используется UI, чтобы показать «Подготовка модели» только при первом
  /// запуске, а не перед каждой транскрибацией.
  /// Текущая фаза подготовки модели (task 067): null — ничего не идёт,
  /// 'download' — Play догружает fast-follow пакет, 'copy' — копируем
  /// модель в рабочую директорию. UI показывает по ней разные подписи.
  static String? phase;

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

  /// Рабочая папка мультиязычной модели Whisper.
  static Future<Directory> whisperModelDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/models/whisper-small');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Готовит мультиязычную модель (EN/DE): копирует из asset pack (AAB) или
  /// из flutter-ассетов (APK). Повторный вызов бесплатен.
  /// Task 078: та же целостность, что у GigaAM — быстрая сверка (маркер +
  /// размеры) на старте, полная (размер+sha256) при копировании/починке;
  /// битый источник → понятная ошибка без нативного краша.
  static Future<void> ensureWhisperReady({
    void Function(int copied, int total)? onProgress,
  }) async {
    final dir = await whisperModelDir();
    final specs = ModelManifest.forPrefix(ModelManifest.whisperPrefix);

    if (_sizesMatch(dir, specs) && await _markerValid(dir, specs)) return;

    debugPrint('[whisper] рабочая копия не прошла проверку — самопочинка');
    await _logSizes(dir, specs, prefix: 'whisper-work(broken)');
    _deleteFiles(dir, specs);
    await _deleteMarker(dir);

    try {
      final packDir = await _assetPackDir();
      if (packDir != null) {
        final src = Directory('$packDir/models/whisper-small');
        if (await _sourceVerified(src, specs)) {
          phase = 'copy';
          await _copyList(src, dir, whisperFiles, onProgress);
          phase = null;
          await _verifyAndMark(dir, specs);
          debugPrint('[whisper] prepared from asset pack (verified)');
          return;
        }
        debugPrint('[whisper] asset pack: whisper повреждена (манифест не сошёлся)');
        await _logSizes(src, specs, prefix: 'whisper-pack(broken)');
      }
    } catch (_) {}

    try {
      var totalBytes = 0;
      for (final s in specs) {
        totalBytes += s.size;
      }
      var copied = 0;
      var bundleOk = true;
      for (final s in specs) {
        final data = await rootBundle
            .load('assets/models/whisper-small/${s.basename}');
        final bytes = data.buffer.asUint8List();
        if (bytes.length != s.size || !_hashMatchesBytes(bytes, s.sha256)) {
          debugPrint('[whisper] bundle assets: ${s.basename} битый '
              '(размер ${bytes.length}, эталон ${s.size})');
          bundleOk = false;
          break;
        }
        await File('${dir.path}/${s.basename}').writeAsBytes(bytes, flush: true);
        copied += bytes.length;
        onProgress?.call(copied, totalBytes);
      }
      if (bundleOk) {
        await _verifyAndMark(dir, specs);
        debugPrint('[whisper] prepared from bundle assets (verified)');
        return;
      }
      // Битый источник — чистим полукопии; следующий запуск повторит починку.
      _deleteFiles(dir, specs);
    } catch (e) {
      debugPrint('[whisper] bundle assets unavailable: $e');
    }
    throw StateError(
      'Мультиязычная модель повреждена и не может быть восстановлена '
      'из установленного пакета. Переустановите приложение.',
    );
  }

  /// Копирование списка файлов из [src] в [dst] с прогрессом.
  static Future<void> _copyList(
    Directory src,
    Directory dst,
    List<String> files,
    void Function(int copied, int total)? onProgress,
  ) async {
    var total = 0;
    for (final f in files) {
      total += File('${src.path}/$f').lengthSync();
    }
    var copied = 0;
    for (final f in files) {
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

  /// Гарантирует, что все файлы модели лежат в [modelDir] и целы.
  /// Вызывать перед каждой транскрибацией — повторный вызов бесплатен.
  /// [onProgress] — (скопировано байт, всего байт) для экрана
  /// «Подготовка модели» при первом запуске (копирование локальное,
  /// без сети, отмены нет — модель обязана оказаться на месте).
  ///
  /// Задача 078 (краш русской расшифровки у тестера: оборванный
  /// encoder.int8.onnx → нативный abort sherpa-onnx, который из Dart не
  /// перехватывается). Защита — валидация ДО загрузки движка:
  ///   • обычный старт — быстрая сверка: маркер нужной версии + размеры
  ///     (хэши не гоняем);
  ///   • при (пере)копировании/починке — полная проверка источника
  ///     (размер + sha256 по абсолютным эталонам манифеста), после копия —
  ///     такая же полная проверка рабочей копии + маркер;
  ///   • рабочая копия битая — самопочинка: удалить и скопировать заново;
  ///   • источник битый/неполный — понятная ошибка (без краша), битая
  ///     рабочая копия удаляется, чтобы следующий запуск повторил починку.
  /// Task 067 (fast-follow) сохранён: ожидание доставки пакета и phase.
  static Future<void> ensureModelReady({
    void Function(int copied, int total)? onProgress,
  }) async {
    if (_prepared) return;
    final dir = await modelDir();
    final specs = ModelManifest.forPrefix(ModelManifest.gigaamPrefix);

    // Быстрый путь (обычный старт): размеры сошлись + маркер той же версии.
    if (_sizesMatch(dir, specs) && await _markerValid(dir, specs)) {
      _prepared = true;
      return;
    }

    // Рабочая копия битая/устарела — самопочинка с нуля.
    debugPrint('[gigaam] рабочая копия не прошла проверку — самопочинка');
    await _logSizes(dir, specs, prefix: 'work(broken)');
    _deleteFiles(dir, specs);
    await _deleteMarker(dir);

    // 1) Play asset pack (AAB). Task 067: пакет fast-follow — Play
    //    догружает его ПОСЛЕ установки. Сначала полная проверка
    //    ИСТОЧНИКА (размер+sha256), потом копирование.
    var packDir = await _assetPackDir();
    if (packDir != null) {
      final src = Directory('$packDir/models/gigaam_v3_punct');
      if (await _sourceVerified(src, specs)) {
        await _logSizes(src, specs, prefix: 'pack');
        phase = 'copy';
        await _copyFrom(src, dir, specs, onProgress);
        phase = null;
        await _verifyAndMark(dir, specs);
        _prepared = true;
        debugPrint('[gigaam] model prepared from asset pack (verified)');
        return;
      }
      debugPrint('[gigaam] asset pack повреждён (манифест не сошёлся)');
      await _logSizes(src, specs, prefix: 'pack(broken)');
    } else if (Platform.isAndroid) {
      // Пакета на диске нет. Либо он ещё догружается (fast-follow),
      // либо это APK-раздача без пакета — разберёмся по статусу.
      final info = await _packInfo();
      if (info.status == GigaamPackStatus.downloading) {
        debugPrint('[gigaam] pack not on disk yet (status=${info.status}), waiting');
        phase = 'download';
        await _waitForPack(onProgress);
        phase = null;
        packDir = await _assetPackDir();
        if (packDir != null) {
          final src = Directory('$packDir/models/gigaam_v3_punct');
          if (await _sourceVerified(src, specs)) {
            phase = 'copy';
            await _copyFrom(src, dir, specs, onProgress);
            phase = null;
            await _verifyAndMark(dir, specs);
            _prepared = true;
            debugPrint('[gigaam] model prepared after fast-follow delivery (verified)');
            return;
          }
          debugPrint('[gigaam] pack arrived but failed verification (broken)');
          await _logSizes(src, specs, prefix: 'pack-arrived(broken)');
        }
        // Догрузился, но модели в нём нет/битая — нештатно, идём к bundle.
        debugPrint('[gigaam] pack arrived without valid model');
      } else if (info.status == GigaamPackStatus.failed) {
        debugPrint('[gigaam] pack delivery failed (code=${info.errorCode})');
      }
      // unknown/completed-пусто: APK-раздача — bundle assets ниже.
    }

    // 2) Flutter assets (APK, прямая раздача): bundle читается целиком
    //    в память; каждый файл сверяем размером+хэшем ДО записи.
    try {
      var totalBytes = 0;
      for (final s in specs) {
        totalBytes += s.size;
      }
      var copiedBytes = 0;
      var bundleOk = true;
      for (final s in specs) {
        final data =
            await rootBundle.load('assets/models/gigaam_v3_punct/${s.basename}');
        final bytes = data.buffer.asUint8List();
        if (bytes.length != s.size || !_hashMatchesBytes(bytes, s.sha256)) {
          debugPrint('[gigaam] bundle assets: ${s.basename} битый '
              '(размер ${bytes.length}, эталон ${s.size})');
          bundleOk = false;
          break;
        }
        final out = File('${dir.path}/${s.basename}');
        await out.writeAsBytes(bytes, flush: true);
        copiedBytes += bytes.length;
        onProgress?.call(copiedBytes, totalBytes);
      }
      if (bundleOk) {
        await _verifyAndMark(dir, specs);
        _prepared = true;
        debugPrint('[gigaam] model prepared from bundle assets (verified)');
        return;
      }
      // Битый источник в bundle — чистим недописанное, чтобы не осталось
      // полукопий; следующий запуск повторит попытку.
      _deleteFiles(dir, specs);
    } catch (e) {
      debugPrint('[gigaam] bundle assets unavailable: $e');
    }

    // Оба источника неисправны. Битая рабочая копия уже удалена —
    // движок не увидит оборванный файл и не упадёт; пользователь получает
    // понятную ошибку вместо краша.
    final report = await integrityReport();
    throw StateError(
      'Модель распознавания повреждена и не может быть восстановлена '
      'из установленного пакета. Переустановите приложение. '
      'Диагностика: $report',
    );
  }

  /// Потоковое копирование модели из [src] в [dst] с точным прогрессом.
  /// Источник к моменту вызова уже полностью проверен (размер+sha256).
  /// Каждый записанный файл сверяется по размеру сразу; sha256 рабочей
  /// копии — в [_verifyAndMark] после копирования всех файлов (ТЗ 078:
  /// хэши при копировании, но не при каждом старте).
  static Future<void> _copyFrom(
    Directory src,
    Directory dst,
    List<ModelFileSpec> specs,
    void Function(int copied, int total)? onProgress,
  ) async {
    var total = 0;
    for (final s in specs) {
      total += File('${src.path}/${s.basename}').lengthSync();
    }
    var copied = 0;
    for (final s in specs) {
      final sf = File('${src.path}/${s.basename}');
      final d = File('${dst.path}/${s.basename}');
      final reader = sf.openRead();
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
      if (d.lengthSync() != s.size) {
        throw StateError('Ошибка копирования модели: ${s.basename}');
      }
    }
  }

  /// Файлы существуют и размеры точно совпадают с манифестом
  /// (раньше было «есть и >0 байт» — оборванная закачка проходила).
  static bool _sizesMatch(Directory d, List<ModelFileSpec> specs) {
    for (final s in specs) {
      final f = File('${d.path}/${s.basename}');
      if (!f.existsSync() || f.lengthSync() != s.size) return false;
    }
    return true;
  }

  static void _deleteFiles(Directory d, List<ModelFileSpec> specs) {
    for (final s in specs) {
      final f = File('${d.path}/${s.basename}');
      if (f.existsSync()) f.deleteSync();
    }
  }

  /// Полная проверка директории: размер + sha256 каждого файла.
  static Future<bool> _verifyFully(
    Directory d,
    List<ModelFileSpec> specs,
  ) async {
    for (final s in specs) {
      final f = File('${d.path}/${s.basename}');
      if (!f.existsSync() || f.lengthSync() != s.size) return false;
      if (!await _hashMatchesFile(f, s.sha256)) return false;
    }
    return true;
  }

  /// Источник пригоден для копирования: все файлы целы по манифесту.
  static Future<bool> _sourceVerified(
    Directory src,
    List<ModelFileSpec> specs,
  ) async {
    if (!src.existsSync()) return false;
    return _verifyFully(src, specs);
  }

  static Future<String> _sha256File(File f) async {
    final sink = _DigestCollector();
    final hasher = sha256.startChunkedConversion(sink);
    await for (final chunk in f.openRead()) {
      hasher.add(chunk);
    }
    hasher.close();
    return sink.value.toString();
  }

  static Future<bool> _hashMatchesFile(File f, String sha256hex) async {
    final h = await _sha256File(f);
    return h.toLowerCase() == sha256hex.toLowerCase();
  }

  static bool _hashMatchesBytes(Uint8List bytes, String sha256hex) {
    final h = sha256.convert(bytes).toString();
    return h.toLowerCase() == sha256hex.toLowerCase();
  }

  // ---------- Маркер verified.json ----------

  static File _markerFile(Directory dir) => File('${dir.path}/verified.json');

  /// Маркер: версия манифеста + эталонные размеры. Быстрый путь доверяет
  /// маркеру только вместе со сверкой фактических размеров — подмена
  /// маркера без целых файлов не проходит.
  static Future<bool> _markerValid(
    Directory dir,
    List<ModelFileSpec> specs,
  ) async {
    final f = _markerFile(dir);
    if (!f.existsSync()) return false;
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if (j['v'] != ModelManifest.version) return false;
      final files = j['files'];
      if (files is! Map) return false;
      for (final s in specs) {
        if (files[s.basename] != s.size) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _writeMarker(
    Directory dir,
    List<ModelFileSpec> specs,
  ) async {
    final files = <String, int>{
      for (final s in specs) s.basename: s.size,
    };
    final f = _markerFile(dir);
    await f
        .writeAsString(jsonEncode({'v': ModelManifest.version, 'files': files}));
  }

  static Future<void> _deleteMarker(Directory dir) async {
    final f = _markerFile(dir);
    if (f.existsSync()) f.deleteSync();
  }

  /// Копия готова: полная проверка (размер + sha256) и только потом маркер.
  static Future<void> _verifyAndMark(
    Directory dir,
    List<ModelFileSpec> specs,
  ) async {
    if (!await _verifyFully(dir, specs)) {
      await _logSizes(dir, specs, prefix: 'work(after-copy,broken)');
      throw StateError(
        'Модель распознавания повреждена при копировании. '
        'Перезапустите приложение — копирование повторится.',
      );
    }
    await _writeMarker(dir, specs);
  }

  /// Диагностика (ТЗ 078 п.5): ожидаемый/фактический размер каждого файла
  /// GigaAM + состояние маркера. Для whisper — то же самое по её спекам,
  /// если понадобится расширить экран диагностики.
  static Future<Map<String, String>> integrityReport() async {
    final dir = await modelDir();
    final specs = ModelManifest.forPrefix(ModelManifest.gigaamPrefix);
    final out = <String, String>{};
    for (final s in specs) {
      final f = File('${dir.path}/${s.basename}');
      final actual = f.existsSync() ? f.lengthSync() : -1;
      out[s.relPath] = '$actual/${s.size}';
    }
    out['verified'] = (await _markerValid(dir, specs)) ? 'yes' : 'no';
    return out;
  }

  static Future<void> _logSizes(
    Directory d,
    List<ModelFileSpec> specs, {
    required String prefix,
  }) async {
    for (final s in specs) {
      final f = File('${d.path}/${s.basename}');
      final actual = f.existsSync() ? f.lengthSync() : -1;
      debugPrint('[gigaam] $prefix ${s.basename}: $actual/${s.size}');
    }
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

  // ---------- Task 067: fast-follow доставка пакета ----------

  /// Коды AssetPackStatus из Play Core (стабильные значения API).
  static const _psUnknown = 0;
  static const _psPending = 1;
  static const _psDownloading = 2;
  static const _psTransferring = 3;
  static const _psCompleted = 4;
  static const _psFailed = 5;
  static const _psCanceled = 6;
  static const _psWaitingForWifi = 7;
  static const _psNotInstalled = 8;

  /// Статус доставки пакета из Play Core (getGigaamPackState).
  static Future<GigaamPackInfo> _packInfo() async {
    if (!Platform.isAndroid) {
      return const GigaamPackInfo(GigaamPackStatus.unknown, 0, 0, null);
    }
    try {
      final m = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('getGigaamPackState');
      if (m == null) {
        return const GigaamPackInfo(GigaamPackStatus.unknown, 0, 0, null);
      }
      final available = m['available'] == true;
      final fromPlay = m['fromPlay'] == true;
      if (available) {
        return const GigaamPackInfo(GigaamPackStatus.completed, 0, 0, null);
      }
      // Из Play — пакет ещё догружается (fast-follow). Не из Play (APK) —
      // пакета не будет вовсе, идём к bundle-ассетам без ожидания.
      return fromPlay
          ? const GigaamPackInfo(GigaamPackStatus.downloading, 0, 0, null)
          : const GigaamPackInfo(GigaamPackStatus.notInstalled, 0, 0, null);
    } catch (_) {
      return const GigaamPackInfo(GigaamPackStatus.unknown, 0, 0, null);
    }
  }

  /// Ждём завершения доставки fast-follow пакета. Опрос статуса раз в 2 с,
  /// прогресс в байтах. Таймаут 15 минут — дальше бросаем StateError,
  /// вызывающий код покажет понятный статус (это не падение приложения).
  static Future<void> _waitForPack(
      void Function(int copied, int total)? onProgress) async {
    // На случай отложенного старта явно запрашиваем доставку.
    try {
      await _channel.invokeMethod<bool>('requestGigaamPack');
    } catch (_) {}
    const timeout = Duration(minutes: 15);
    final start = DateTime.now();
    while (true) {
      final info = await _packInfo();
      if (info.status == GigaamPackStatus.completed) return;
      if (info.status == GigaamPackStatus.failed) {
        throw StateError(
            'Не удалось загрузить модель распознавания (Play, код ${info.errorCode}). '
            'Проверьте сеть и повторите.');
      }
      if (info.totalBytes > 0) {
        onProgress?.call(info.bytesDownloaded, info.totalBytes);
      } else {
        // Размер ещё неизвестен — крутим индетерминированный прогресс.
        onProgress?.call(0, 0);
      }
      if (DateTime.now().difference(start) > timeout) {
        throw StateError(
            'Модель распознавания не загрузилась за 15 минут. '
            'Проверьте сеть и повторите.');
      }
      await Future<void>.delayed(const Duration(seconds: 2));
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
    String language = 'ru',
    void Function(int done, int total)? onProgress,
    void Function(int done, int total, String text)? onPartial,
    void Function(String line)? onLog,
  }) async {
    await ensureModelReady();
    final dir = (await modelDir()).path;
    var whisperDir = '';
    if (language != 'ru') {
      await ensureWhisperReady();
      whisperDir = (await whisperModelDir()).path;
    }
    final receivePort = ReceivePort();
    late Isolate isolate;
    final threadsOverride = await GigaamService.readThreadsOverride();
    isolate = await Isolate.spawn<_GigaamJob>(
      _gigaamIsolateEntry,
      _GigaamJob(
        modelDir: dir,
        wavPath: wavPath,
        skipChunks: skipChunks,
        progressPort: receivePort.sendPort,
        threads: threadsOverride,
        language: language,
        whisperDir: whisperDir,
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
            try {
              final raw = message.length > 2 ? message[2] : null;
              lastPartTimes = (raw is List)
                  ? raw
                      .map((e) => (e as List)
                          .map((v) => (v as num).toDouble())
                          .toList())
                      .toList()
                  : <List<double>>[];
            } catch (_) {
              lastPartTimes = <List<double>>[];
            }
            try {
              final rawc = message.length > 3 ? message[3] : null;
              lastChunkWordCounts = (rawc is List)
                  ? rawc.map((e) => (e as num).toInt()).toList()
                  : <int>[];
            } catch (_) {
              lastChunkWordCounts = <int>[];
            }
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
  /// Настоящие времена расшифрованных кусков последнего прогона:
  /// [[start, end], ...] в секундах, в том же порядке, что и слова в тексте.
  static List<List<double>> lastPartTimes = <List<double>>[];

  /// Число слов в каждом расшифрованном куске (в том же порядке) — для точных
  /// таймкодов: слово k текста ↔ дробная позиция внутри куска.
  static List<int> lastChunkWordCounts = <int>[];

  /// Спидтюнинг: число потоков задаётся файлом threads.txt (1..8)
  /// в папке приложения — без пересборки. Иначе дефолт 4.
  static Future<int> readThreadsOverride() async {
    try {
      final dir = await TranscribeKeepAlive.filesDir();
      if (dir == null) return 4;
      final f = File('${dir.path}/threads.txt');
      if (await f.exists()) {
        final v = int.tryParse((await f.readAsString()).trim());
        if (v != null && v >= 1 && v <= 8) return v;
      }
    } catch (_) {}
    return 4;
  }

  static Future<String?> transcribeWithGlossary(
    String wavPath, {
    int skipChunks = 0,
    String language = 'ru',
    void Function(int done, int total)? onProgress,
    void Function(int done, int total, String text)? onPartial,
    void Function(String line)? onLog,
  }) async {
    final text = await transcribe(wavPath,
        language: language,
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

/// Task 067: статус доставки fast-follow пакета (Play Asset Delivery).
enum GigaamPackStatus {
  /// пакет на диске, можно копировать модель
  completed,

  /// пакет скачивается/переносится (pending/downloading/transferring/wifi)
  downloading,

  /// пакет не установлен или статус неизвестен (APK-раздача)
  notInstalled,

  /// доставка завершилась с ошибкой
  failed,

  /// статус недоступен (не Android / нет Play Core)
  unknown,
}

/// Снимок статуса пакета: статус + байтовый прогресс доставки.
class GigaamPackInfo {
  final GigaamPackStatus status;
  final int bytesDownloaded;
  final int totalBytes;

  /// Код ошибки Play Core (только при status == failed).
  final int? errorCode;
  const GigaamPackInfo(
      this.status, this.bytesDownloaded, this.totalBytes, this.errorCode);
}

class _GigaamJob {
  final String modelDir;
  final String wavPath;
  final int skipChunks;
  final SendPort progressPort;
  final int threads;
  final String language;
  final String whisperDir;
  const _GigaamJob({
    required this.modelDir,
    required this.wavPath,
    this.skipChunks = 0,
    required this.progressPort,
    this.threads = 4,
    this.language = 'ru',
    this.whisperDir = '',
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
          numThreads: job.threads,
          debug: false,
        ),
      ),
    );

    // --- Мультиязычные языки (EN/DE/…): Whisper small int8 ---
    if (job.language != 'ru') {
      recognizer?.free();
      recognizer = sherpa.OfflineRecognizer(
        sherpa.OfflineRecognizerConfig(
          // Whisper ждёт стандартные 80-мерные признаки (у GigaAM — 64).
          feat: const sherpa.FeatureConfig(sampleRate: 16000, featureDim: 80),
          model: sherpa.OfflineModelConfig(
            whisper: sherpa.OfflineWhisperModelConfig(
              encoder: '${job.whisperDir}/small-encoder.int8.onnx',
              decoder: '${job.whisperDir}/small-decoder.int8.onnx',
              language: job.language,
              task: 'transcribe',
            ),
            tokens: '${job.whisperDir}/small-tokens.txt',
            numThreads: job.threads,
            debug: false,
          ),
        ),
      );
    }

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
        // Task 045: было 1 → 4. Спидтюнинг 29.09: значение можно
        // переопределить файлом threads.txt в папке приложения.
        numThreads: job.threads,
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

    final chunkTimes = <List<double>>[];
    final chunkWords = <int>[];

    void decodeOne(Float32List raw, int gStart, int gEnd) {
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
        if (text.isNotEmpty) {
          parts.add(text);
          chunkTimes.add([gStart / 16000.0, gEnd / 16000.0]);
          chunkWords.add(
              text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length);
        }
        if (idx % 5 == 0) {
          // Задача 036: каждые 5 кусков отдаём накопленный текст наружу,
          // чтобы он сохранился на диск в обход изолята.
          job.progressPort.send(['partial', idx, planned, parts.join(' ')]);
        }
      } finally {
        stream.free();
      }
    }

    void decodeSegment(Float32List raw, int gStart) {
      if (raw.length <= maxSegSamples) {
        decodeOne(raw, gStart, gStart + raw.length);
        return;
      }
      var start = 0;
      while (start < raw.length) {
        var end = start + maxSegSamples;
        if (end >= raw.length) {
          decodeOne(Float32List.sublistView(raw, start, raw.length),
              gStart + start, gStart + raw.length);
          break;
        }
        final winFrom = (end - searchSamples) > (start + minSegSamples)
            ? (end - searchSamples)
            : (start + minSegSamples);
        final q = findQuiet(raw, winFrom, end);
        if (q > start + minSegSamples && q < end) end = q;
        decodeOne(Float32List.sublistView(raw, start, end),
            gStart + start, gStart + end);
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
    final segStarts = <int>[];
    const chunk = 512;
    var offset = 0;
    while (offset < total) {
      final end = (offset + chunk > total) ? total : offset + chunk;
      vad.acceptWaveform(Float32List.sublistView(samples, offset, end));
      offset = end;
      while (!vad.isEmpty()) {
        vadSegs++;
        segLens.add(vad.front().samples.length);
        segStarts.add(vad.front().start);
        segs.add(Float32List.fromList(vad.front().samples));
        vad.pop();
      }
    }
    vad.flush();
    while (!vad.isEmpty()) {
      vadSegs++;
      segLens.add(vad.front().samples.length);
      segStarts.add(vad.front().start);
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
    for (var i = 0; i < segs.length; i++) {
      decodeSegment(segs[i], i < segStarts.length ? segStarts[i] : 0);
    }

    job.progressPort.send([
      'log',
      'vad segments=$vadSegs decoded=$idx parts=${parts.length} '
          'lens=${segLens.take(40).join(',')}'
    ]);

    job.progressPort.send(['done', parts.join(' '), chunkTimes, chunkWords]);
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


/// Локальный коллектор одного Digest для chunked-хеширования
/// (замена DigestSink — исправление ошибки компиляции при приёмке 078, 03.10).
class _DigestCollector implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}
