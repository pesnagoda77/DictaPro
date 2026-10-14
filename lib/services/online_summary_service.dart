// Task 059 + 064: клиент онлайн-итогов (наш Cloudflare Worker).
// Task 098: длинные записи — gzip + нарезка на части (~6–8 тыс. символов
// по границам предложений) + режимы chunk/final + ретраи (сетевой обрыв
// больших POST на канале до Cloudflare; прямое РФ-соединение проходит
// только ~9–14 КБ стабильно).
// Task 105: авторизация через Bearer-токен (SessionService) вместо
// общего x-app-key; audioMs шлём в первом запросе файла; сервер списывает
// часы; обрабатываем 402 (нехватка часов) и 401 (обновление токена).
//
// Сервер: https://dicta-summary.pesnagoda77.workers.dev (POST /summarize,
// заголовок Authorization: Bearer <token> + User-Agent).
// Content-Encoding: gzip — task 098.
//
// Секрет x-app-key НЕ в репозитории: передаётся при сборке через
// --dart-define=DICTA_APP_KEY=... (в CI — GitHub Secrets). Версия для
// User-Agent — --dart-define=DICTA_APP_VERSION=... (fallback 'dev').
//
// Кэш «файл + язык»: повтор по тем же настройкам бесплатен — не списывает
// часы. Часы списываются сервером при успешном ответе.
import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'session_service.dart';

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

  /// Task 105: Bearer-токен из SessionService (fallback на x-app-key
  /// для переходного периода).
  static const _appKey = String.fromEnvironment('DICTA_APP_KEY');
  static const _appVersion = String.fromEnvironment('DICTA_APP_VERSION',
      defaultValue: 'dev');

  /// Файлы, для которых audioMs уже отправлен (один раз на файл).
  final Set<String> _audioMsSent = {};

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
  /// (для списания ИИ-часов сервером, 1 ИИ-час = 1 час аудио).
  /// [lang] — язык интерфейса/транскрипта (кэш по «запись + язык»).
  ///
  /// Task 105: сервер списывает часы. Мы шлём audioMs один раз на файл
  /// (в первом запросе). Ответ 200 → обновляем баланс из balanceMs.
  /// Ответ 402 → InsufficientException с деталями для UI.
  /// Ответ 401 → обновляем токен, повторяем один раз.
  ///
  /// Возвращает null при любой другой ошибке — UI показывает аккуратный
  /// снекбар «не удалось получить итоги, попробуйте позже».
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

    // Task 105: проверяем токен перед запросом
    final token = await SessionService.instance.ensureToken();
    if (token == null && _appKey.isEmpty) {
      debugPrint('[online-summary] нет ни токена, ни x-app-key — запрос отменён');
      return null;
    }

    // audioMs — один раз на файл
    final sendAudioMs = !_audioMsSent.contains(fileId);
    if (sendAudioMs) _audioMsSent.add(fileId);

    String? summaryText;
    try {
      if (utf8.encode(text).length <= _singleMaxBytes) {
        summaryText = await _summarizeSingle(text, lang, audioMs, deviceId,
            token: token, sendAudioMs: sendAudioMs);
      } else {
        summaryText = await _summarizeChunked(text, lang, deviceId,
            token: token, audioMs: sendAudioMs ? audioMs : null);
      }
    } on InsufficientException {
      rethrow; // прокидываем 402 наверх для UI
    } catch (e) {
      debugPrint('[online-summary] ошибка: $e');
      return null;
    }

    if (summaryText == null || summaryText.isEmpty) return null;

    await _writeCache(key, summaryText);
    return OnlineSummaryResult(
      text: summaryText,
      aiHoursSpent: 0, // сервер списал, мы только показываем
      fromCache: false,
    );
  }

  /// Одиночный режим (короткие тексты): один запрос, тело без mode.
  /// Task 105: Bearer-токен, audioMs один раз на файл.
  Future<String?> _summarizeSingle(
      String text, String lang, int audioMs, String? deviceId,
      {String? token, bool sendAudioMs = true}) async {
    final body = jsonEncode({
      'text': text,
      'lang': lang,
      if (sendAudioMs) 'audioMs': audioMs,
      if (deviceId != null) 'device_id': deviceId,
    });
    final resp = await _postGzip(body, token: token);
    if (resp == null) return null;
    return (jsonDecode(resp) as Map<String, dynamic>)['summary'] as String?;
  }

  /// Длинные тексты: части → mode:"chunk" → mode:"final".
  /// Task 105: audioMs шлём в первом chunk-запросе (один раз на файл).
  Future<String?> _summarizeChunked(
      String text, String lang, String? deviceId,
      {String? token, int? audioMs}) async {
    final chunks = _splitIntoChunks(text, _chunkChars);
    debugPrint('[online-summary] нарезка: ${text.length} симв. → '
        '${chunks.length} частей');

    final notes = <String>[];
    for (var i = 0; i < chunks.length; i++) {
      final body = jsonEncode({
        'text': chunks[i],
        'lang': lang,
        'mode': 'chunk',
        if (i == 0 && audioMs != null) 'audioMs': audioMs,
        if (deviceId != null) 'device_id': deviceId,
      });
      final resp = await _postGzip(body, token: token);
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
      if (deviceId != null) 'device_id': deviceId,
    });
    final resp = await _postGzip(finalBody, token: token);
    if (resp == null) return null;
    return (jsonDecode(resp) as Map<String, dynamic>)['summary'] as String?;
  }

  /// POST с gzip-сжатием тела и ретраями.
  /// Task 105: Authorization: Bearer вместо x-app-key (fallback на старый
  /// ключ для переходного периода). При 401 — обновляем токен и повторяем
  /// один раз. При 402 — InsufficientException. При 200 — обновляем
  /// баланс из balanceMs в ответе.
  /// Возвращает тело ответа (200) или null после исчерпания попыток.
  Future<String?> _postGzip(String jsonBody, {String? token}) async {
    final compressed = gzip.encode(utf8.encode(jsonBody));
    var usedToken = token;

    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final headers = <String, String>{
          'Content-Type': 'application/json',
          'Content-Encoding': 'gzip',
          'User-Agent': 'dicta-android/$_appVersion',
        };
        // Task 105: Bearer в приоритете, x-app-key — fallback
        if (usedToken != null && usedToken.isNotEmpty) {
          headers['Authorization'] = 'Bearer $usedToken';
        } else if (_appKey.isNotEmpty) {
          headers['x-app-key'] = _appKey;
        }

        final resp = await http
            .post(
              Uri.parse(_endpoint),
              headers: headers,
              body: compressed,
            )
            .timeout(_timeout);

        if (resp.statusCode == 401) {
          // Токен истёк — обновляем и повторяем (не считаем попытку)
          debugPrint('[online-summary] 401 — обновляем токен');
          final newToken = await SessionService.instance.refreshSession();
          if (newToken.ok && newToken.token != null) {
            usedToken = newToken.token;
            continue;
          }
          return null;
        }

        if (resp.statusCode == 402) {
          // Не хватает ИИ-часов
          debugPrint('[online-summary] 402 — нехватка часов');
          try {
            final data = jsonDecode(resp.body) as Map<String, dynamic>;
            throw InsufficientException(
              leftMs: (data['leftMs'] as num?)?.toInt() ?? 0,
              needMs: (data['needMs'] as num?)?.toInt() ?? 0,
            );
          } catch (_) {
            throw const InsufficientException(leftMs: 0, needMs: 0);
          }
        }

        if (resp.statusCode != 200) {
          debugPrint('[online-summary] HTTP ${resp.statusCode} '
              '(попытка $attempt/$_maxAttempts)');
          if (resp.statusCode >= 400 &&
              resp.statusCode < 500 &&
              resp.statusCode != 408 &&
              resp.statusCode != 429) {
            return null;
          }
        } else {
          // 200 — обновляем баланс из ответа
          try {
            final data = jsonDecode(resp.body) as Map<String, dynamic>;
            final balMs = (data['balanceMs'] as num?)?.toInt();
            if (balMs != null) {
              SessionService.instance.updateBalanceFromSummary(balMs);
            }
          } catch (_) {}
          return resp.body;
        }
      } on InsufficientException {
        rethrow;
      } catch (e) {
        debugPrint('[online-summary] попытка $attempt/$_maxAttempts: $e');
      }
      if (attempt < _maxAttempts) {
        await Future.delayed(Duration(seconds: attempt));
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

/// Task 105: сервер вернул 402 — не хватает ИИ-часов.
/// UI ловит и показывает понятное сообщение.
class InsufficientException implements Exception {
  final int leftMs;
  final int needMs;
  const InsufficientException({required this.leftMs, required this.needMs});

  double get leftHours => leftMs / 3600000.0;
  double get needHours => needMs / 3600000.0;

  @override
  String toString() =>
      'InsufficientException(left=${leftHours.toStringAsFixed(1)}h, '
      'need=${needHours.toStringAsFixed(1)}h)';
}
