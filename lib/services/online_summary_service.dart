// Task 059: клиент онлайн-итогов (Cloudflare Worker, эконом-модель).
//
// Серверную часть (Worker + авторизацию подписок + хостинг модели) делает
// главный агент. Здесь — клиент: отправка текста, кэш «файл + настройки»
// (повтор по тем же настройкам бесплатен — не списывает часы), учёт часов.
//
// Endpoint зашит как константу — заменить на реальный при поднятии Worker'а.
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

  // TODO(Claude): подставить реальный URL Worker'а при поднятии сервера.
  static const endpoint = 'https://dictapro-summaries.example.com/api/summary';
  static const _timeout = Duration(seconds: 90);
  static const _kCache = 'online_summary_cache_v1';

  /// Ключ кэша: файл + настройки (текст может обновиться после
  /// дозаписи расшифровки — hash транскрипта внутри).
  static String _cacheKey(String fileId, String settingsHash) =>
      '$fileId|$settingsHash';

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

  /// Сводка настроек, от которых зависит результат: длина, наличие
  /// диаризации/глазарея и т.п. — повтор с теми же настройками = тот же
  /// кэш. Сейчас настройки онлайн-итогов фиксированы, hash константный,
  /// но структура позволяет добавить параметры без миграции кэша.
  static String settingsHash({int variant = 0}) => 'v$variant';

  /// Отправить текст на сервер. [audioMs] — длительность записи (для
  /// списания ИИ-часов). Часы списываются ТОЛЬКО при успешном ответе,
  /// свежий ответ кладётся в кэш.
  Future<OnlineSummaryResult?> summarize({
    required String fileId,
    required String text,
    required int audioMs,
    String? deviceId,
  }) async {
    final key = _cacheKey(fileId, settingsHash());
    final cached = await _readCache(key);
    if (cached != null) return cached;

    try {
      final resp = await http
          .post(
            Uri.parse(endpoint),
            headers: const {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'text': text,
              'audio_ms': audioMs,
              'device_id': deviceId,
            }),
          )
          .timeout(_timeout);

      if (resp.statusCode != 200) {
        debugPrint('[online-summary] HTTP ${resp.statusCode}');
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
