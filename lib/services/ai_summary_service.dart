import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// ИИ-саммари записей через Z.ai (GLM-4.5-Flash — бесплатный).
/// Ключ пользователя хранится в SharedPreferences (BYOK).
/// При отсутствии ключа/ошибке — возвращает null, вызывающий код
/// откатывается на офлайн-саммари (EnhancedSummaryService).
class AiSummaryService {
  static const String _apiUrlCoding =
      'https://api.z.ai/api/coding/paas/v4/chat/completions';
  static const String _apiUrl =
      'https://api.z.ai/api/paas/v4/chat/completions';
  static const String _model = 'glm-4.5-flash';
  static const String _keyName = 'zai_api_key';

  static Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final k = prefs.getString(_keyName);
    if (k == null || k.trim().isEmpty) return null;
    return k.trim();
  }

  static Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyName, key.trim());
  }

  /// Промпт-структура (из исследования: AssemblyAI + Fireflies практики).
  static String _buildPrompt(String transcript, String? userNotes) {
    final notes = (userNotes == null || userNotes.trim().isEmpty)
        ? '(нет)'
        : userNotes.trim();
    return '''РОЛЬ: Ты — профессиональный аналитик встреч. Извлекай только то, что реально прозвучало в транскрипте. Если элемента нет — напиши «не обсуждалось», ничего не выдумывай.

ЗАМЕТКИ ПОЛЬЗОВАТЕЛЯ (приоритетный контекст, если есть):
$notes

СТРУКТУРА ОТВЕТА (Markdown):
## Обзор
— главная цель и суть в 2–3 предложениях.
## Ключевые решения
— каждое решение отдельным пунктом; сроки и цифры, если прозвучали.
## Задачи (action items)
— [ ] задача — владелец — срок (если указан).
## Основные темы
— по каждой теме 1–2 тезиса, спорные моменты, открытые вопросы.
## Имена, даты, числа
— списком всё существенное.
## Следующие шаги
— договорённости, что подготовить.

Если запись похожа на лекцию — вместо решений/задач сделай «Конспект по разделам» и «Термины и определения». Если это личные мысли — «Ядро идеи» и «Что развить».

ТРАНСКРИПТ:
$transcript''';
  }

  /// Возвращает Markdown-саммари или null (нет ключа / ошибка сети / лимит).
  static Future<String?> generate(String transcript, {String? userNotes}) async {
    if (transcript.trim().isEmpty) return null;
    final apiKey = await getApiKey();
    if (apiKey == null) return null;

    // Ограничиваем вход: 60 тыс. знаков ≈ ~13k токенов (хватает на час речи)
    var text = transcript;
    if (text.length > 60000) text = text.substring(0, 60000);

    final body = jsonEncode({
      'model': _model,
      'messages': [
        {'role': 'system', 'content': 'Ты — аналитик встреч и лекций. Пиши только по транскрипту, без выдумок.'},
        {'role': 'user', 'content': _buildPrompt(text, userNotes)},
      ],
      'temperature': 0.3,
      'max_tokens': 3000,
    });

    for (final url in [_apiUrlCoding, _apiUrl]) {
      try {
        final resp = await http
            .post(Uri.parse(url), headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            }, body: body)
            .timeout(const Duration(seconds: 60));
        if (resp.statusCode == 200) {
          final j = jsonDecode(resp.body) as Map<String, dynamic>;
          final choices = j['choices'] as List<dynamic>?;
          if (choices != null && choices.isNotEmpty) {
            final content = choices[0]['message']['content'] as String?;
            if (content != null && content.trim().isNotEmpty) {
              return content.trim();
            }
          }
        }
      } catch (_) {
        // пробуем следующий эндпоинт
      }
    }
    return null;
  }
}
