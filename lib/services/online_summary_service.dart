// Task 059 + 064: клиент онлайн-итогов (наш Cloudflare Worker).
// Task 098: длинные записи — gzip + нарезка на части (~6–8 тыс. символов
// по границам предложений) + режимы chunk/final + ретраи (сетевой обрыв
// больших POST на канале до Cloudflare; прямое РФ-соединение проходит
// только ~9–14 КБ стабильно).
//
// Сервер: https://dicta-summary.pesnagoda77.workers.dev (POST /summarize,
// заголовки x-app-key + User-Agent — без UA Cloudflare даёт 403/1010;
// Content-Encoding: gzip — task 098).
//
// Секрет x-app-key НЕ в репозитории: передаётся при сборке через
// --dart-define=DICTA_APP_KEY=... (в CI — GitHub Secrets). Версия для
// User-Agent — --dart-define=DICTA_APP_VERSION=... (fallback 'dev').
//
// Кэш «файл + язык»: повтор по тем же настройкам бесплатен — не списывает
// часы. Часы списываются ТОЛЬКО при успешном ответе (один раз за итог).
import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_hours_service.dart';

class OnlineSummaryResult {
  final String text;
  final double aiHoursSpent;
  final bool fromCache;
  const OnlineSummaryResult({
    required this.text,
    required this.aiHoursSpent,
    required this.fromCache,
  });
}

class OnlineSummaryService {
  OnlineSummaryService._();
  static final OnlineSummaryService instance = OnlineSummaryService._();

  // Task 064: реальный Worker (было: example.com placeholder).
  static const _endpoint =
      'https://dicta-summary.pesnagoda77.workers.dev/summarize';
  // Task 098: 90 с — часовая запись по нарезанным частям проходит за 1–2 с
  // на часть, но финальный запрос и повторы должны успевать при плохом канале.
  static const _timeout = Duration(seconds: 90);

  /// Секрет из --dart-define. Пустой при локальной разработке —
  /// сервер вернёт 401, клиент покажет аккуратную ошибку.
  static const _appKey = String.fromEnvironment('DICTA_APP_KEY');
  static const _appVersion = String.fromEnvironment('DICTA_APP_VERSION',
      defaultValue: 'dev');

  static const _kCache = 'online_summary_cache_v1';

  // Task 098: пороги проверены тестами Краба (11.10): прямое РФ-соединение
  // стабильно проходит тела ~9–14 КБ; ~20 КБ+ — обрыв. До 12 КБ utf8 —
  // одиночный режим (как раньше, регресс не допускается). Больше — нарезка
  // на части ~7000 символов (gz ≈ 6–8 КБ) → chunk → final.
  static const _singleMaxBytes = 12000;
  static const _chunkChars = 7000;
  static const _maxAttempts = 3; // 1 основная + 2 ретрая (task 098)

  /// Ключ кэша: файл + настройки + язык (повтор по тому же языку бесплатен).
  static String _cacheKey(String fileId, String settingsHash, String lang) =>
      '$fileId|$settingsHash|$lang';

  Future<OnlineSummaryResult?> _readCache(String key) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('$_kCache::$key');
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return OnlineSummaryResult(
        text: m['text'] as String,
        aiHoursSpent: 0, // повтор по тем же настройкам — бесплатен
        fromCache: true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String key, String text) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('$_kCache::$key',
        jsonEncode({'text': text, 'ts': DateTime.now().toIso8601String()}));
  }

  /// Сводка настроек, от которых зависит результат. Сейчас настройки
  /// онлайн-итогов фиксированы, hash константный, но структура позволяет
  /// добавить параметры без миграции кэша.
  static String settingsHash({int variant = 0}) => 'v$variant';

  /// Отправить текст на наш воркер. [audioMs] — длительность записи
  /// (для списания ИИ-часов, 1 ИИ-час = 1 час аудио). [lang] — язык
  /// интерфейса/транскрипта (кэш по «запись + язык»).
  ///
  /// Возвращает null при любой ошибке — UI показывает аккуратный снекбар
  /// «не удалось получить итоги, попробуйте позже» (task 064, без падений).
  Future<OnlineSummaryResult?> summarize({
    required String fileId,
    required String text,
    required int audioMs,
    String lang = 'ru',
    String? deviceId,
  }) async {
    final key = _cacheKey(fileId, settingsHash(), lang);
    final cached = await _readCache(key);
    if (cached != null) return cached;

    if (_appKey.isEmpty) {
      debugPrint('[online-summary] DICTA_APP_KEY не задан — запрос отменён');
      return null;
    }

    String? summaryText;
    try {
      if (utf8.encode(text).length <= _singleMaxBytes) {
        // Короткая запись: одиночный режим, как раньше (task 064/059).
        summaryText = await _summarizeSingle(text, lang, audioMs, deviceId);
      } else {
        // Длинная запись: нарезка → конспекты частей → итог (task 098).
        summaryText = await _summarizeChunked(text, lang, deviceId);
      }
    } catch (e) {
      debugPrint('[online-summary] ошибка: $e');
      return null;
    }

    if (summaryText == null || summaryText.isEmpty) return null;

    final spent = await AiHoursService.instance.spend(audioMs);
    if (spent <= 0) {
      // Пограничный случай: сервер ответил, а баланс кончился между
      // проверкой и ответом — показываем результат, часы не списаны;
      // серверная авторизация всё равно не пропустит следующий запрос.
      debugPrint('[online-summary] баланс 0 при живом ответе');
    }
    await _writeCache(key, summaryText);
    return OnlineSummaryResult(
      text: summaryText,
      aiHoursSpent: spent,
      fromCache: false,
    );
  }

  /// Одиночный режим (короткие тексты): один запрос, тело без mode —
  /// поведение воркера без изменений (совместимость, task 098).
  Future<String?> _summarizeSingle(
      String text, String lang, int audioMs, String? deviceId) async {
    final body = jsonEncode({
      'text': text,
      'lang': lang,
      'audio_ms': audioMs,
      'device_id': deviceId,
    });
    final resp = await _postGzip(body);
    if (resp == null) return null;
    return (jsonDecode(resp) as Map<String, dynamic>)['summary'] as String?;
  }

  /// Длинные тексты: части (~7000 символов по границам предложений) →
  /// mode:"chunk" (краткий конспект: решения/задачи/цифры/даты) →
  /// mode:"final" (итог по конспектам частей). Часы НЕ списываются за
  /// части — только один раз за успешный итог в summarize().
  Future<String?> _summarizeChunked(
      String text, String lang, String? deviceId) async {
    final chunks = _splitIntoChunks(text, _chunkChars);
    debugPrint('[online-summary] нарезка: ${text.length} симв. → '
        '${chunks.length} частей');

    final notes = <String>[];
    for (var i = 0; i < chunks.length; i++) {
      final body = jsonEncode({
        'text': chunks[i],
        'lang': lang,
        'mode': 'chunk',
        'device_id': deviceId,
      });
      final resp = await _postGzip(body);
      if (resp == null) {
        debugPrint('[online-summary] часть ${i + 1}/${chunks.length} '
            'не прошла после ретраев');
        return null;
      }
      final note =
          (jsonDecode(resp) as Map<String, dynamic>)['summary'] as String?;
      if (note == null || note.trim().isEmpty) return null;
      notes.add('Часть ${i + 1}:\n$note');
    }

    final finalBody = jsonEncode({
      'text': notes.join('\n\n'),
      'lang': lang,
      'mode': 'final',
      'device_id': deviceId,
    });
    final resp = await _postGzip(finalBody);
    if (resp == null) return null;
    return (jsonDecode(resp) as Map<String, dynamic>)['summary'] as String?;
  }

  /// POST с gzip-сжатием тела (Content-Encoding: gzip) и ретраями.
  /// Возвращает тело ответа (200) или null после исчерпания попыток.
  Future<String?> _postGzip(String jsonBody) async {
    final compressed = gzip.encode(utf8.encode(jsonBody));
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final resp = await http
            .post(
              Uri.parse(_endpoint),
              headers: {
                'Content-Type': 'application/json',
                'Content-Encoding': 'gzip',
                'x-app-key': _appKey,
                'User-Agent': 'dicta-android/$_appVersion',
              },
              body: compressed,
            )
            .timeout(_timeout);

        if (resp.statusCode != 200) {
          debugPrint('[online-summary] HTTP ${resp.statusCode} '
              '(попытка $attempt/$_maxAttempts): '
              '${resp.body.substring(0, resp.body.length > 200 ? 200 : resp.body.length)}');
          // 4xx (кроме 408/429) — ретрай бессмысленен, ошибка постоянна.
          if (resp.statusCode >= 400 &&
              resp.statusCode < 500 &&
              resp.statusCode != 408 &&
              resp.statusCode != 429) {
            return null;
          }
        } else {
          return resp.body;
        }
      } catch (e) {
        debugPrint('[online-summary] попытка $attempt/$_maxAttempts: $e');
      }
      if (attempt < _maxAttempts) {
        await Future.delayed(Duration(seconds: attempt)); // 1 с, затем 2 с
      }
    }
    return null;
  }

  /// Нарезка текста на части не больше [chunkSize] символов по границам
  /// предложений (. ! ? … и переносы строк). Если границы ближе чем
  /// половина части к концу — ищем пробел; иначе режем жёстко
  /// (страховка от бесконечного цикла на тексте без пунктуации).
  static List<String> _splitIntoChunks(String text, int chunkSize) {
    if (text.length <= chunkSize) return [text];
    final chunks = <String>[];
    var start = 0;
    while (start < text.length) {
      if (text.length - start <= chunkSize) {
        chunks.add(text.substring(start));
        break;
      }
      var end = start + chunkSize;
      var cut = -1;
      const sentenceEnds = '.!?…\n';
      for (var i = end - 1; i > start + chunkSize ~/ 2; i--) {
        if (sentenceEnds.contains(text[i])) {
          cut = i + 1;
          break;
        }
      }
      if (cut < 0) {
        final space = text.lastIndexOf(' ', end - 1);
        if (space > start + chunkSize ~/ 2) cut = space + 1;
      }
      if (cut <= start) cut = end; // жёсткий рез без пунктуации/пробелов
      chunks.add(text.substring(start, cut));
      start = cut;
    }
    return chunks;
  }
}
