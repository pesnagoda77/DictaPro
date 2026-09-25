// Task 059 + 064: клиент онлайн-итогов (наш Cloudflare Worker).
//
// Сервер: https://dicta-summary.pesnagoda77.workers.dev (POST /summarize,
// заголовки x-app-key + User-Agent — без UA Cloudflare даёт 403/1010).
//
// Секрет x-app-key НЕ в репозитории: передаётся при сборке через
// --dart-define=DICTA_APP_KEY=... (в CI — GitHub Secrets). Версия для
// User-Agent — --dart-define=DICTA_APP_VERSION=... (fallback 'dev').
//
// Кэш «файл + язык»: повтор по тем же настройкам бесплатен — не списывает
// часы. Часы списываются ТОЛЬКО при успешном ответе.
import 'dart:convert';

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
  static const _timeout = Duration(seconds: 60); // требование задачи 064

  /// Секрет из --dart-define. Пустой при локальной разработке —
  /// сервер вернёт 401, клиент покажет аккуратную ошибку.
  static const _appKey = String.fromEnvironment('DICTA_APP_KEY');
  static const _appVersion = String.fromEnvironment('DICTA_APP_VERSION',
      defaultValue: 'dev');

  static const _kCache = 'online_summary_cache_v1';

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

    try {
      final resp = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'x-app-key': _appKey,
              'User-Agent': 'dicta-android/$_appVersion',
            },
            body: jsonEncode({
              'text': text,
              'lang': lang,
              'audio_ms': audioMs,
              'device_id': deviceId,
            }),
          )
          .timeout(_timeout);

      if (resp.statusCode != 200) {
        debugPrint(
            '[online-summary] HTTP ${resp.statusCode}: ${resp.body.substring(0, resp.body.length > 200 ? 200 : resp.body.length)}');
        return null;
      }
      final m = jsonDecode(resp.body) as Map<String, dynamic>;
      final summaryText = (m['summary'] as String?)?.trim() ?? '';
      if (summaryText.isEmpty) return null;

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
    } catch (e) {
      debugPrint('[online-summary] ошибка: $e');
      return null;
    }
  }
}
