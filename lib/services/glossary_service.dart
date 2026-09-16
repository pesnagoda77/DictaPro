// Глоссарий терминов записи + хранилище «горячих слов» пользователя.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

//
// Зачем: алфавит GigaAM — кириллица, поэтому латиница и аббревиатуры
// («in vivo», «DCAD», «NEB») физически не могут быть выданы моделью —
// она пишет их «на слух» («нвиво», «инсака»). Лечим на уровне текста:
// пользователь вписывает термины в поле «Термины этой записи», и мы
// точно подставляем их, если в тексте есть близкое звучание.
//
// Это не внутренний словарь-костыль: список задаёт сам пользователь,
// он пустой по умолчанию, и без него текст не меняется.
/// «Горячие слова» пользователя: последние введённые термины записи.
/// Сохраняем, чтобы предлагать повторно (чипы на экране записи).
/// (task 019: перенесено из удалённого local_text_cleanup.dart — сама
/// чистка текста убрана вместе с VOSK, термины нужны глоссарию GigaAM.)
class HotwordsStorage {
  static const _key = 'last_hotwords';
  static const _max = 12;

  /// Разбор поля «Термины этой записи» (через запятую).
  static List<String> parse(String raw) => raw
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();

  static Future<List<String>> recent() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_key);
    if (s == null || s.isEmpty) return [];
    try {
      return (jsonDecode(s) as List).map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  /// Новые термины — в начало списка, дедупликация без учёта регистра.
  static Future<void> remember(List<String> words) async {
    if (words.isEmpty) return;
    final prev = await recent();
    final merged = <String>[];
    for (final w in [...words.reversed, ...prev]) {
      final lw = w.toLowerCase();
      if (!merged.any((e) => e.toLowerCase() == lw)) merged.add(w);
      if (merged.length >= _max) break;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(merged));
  }
}

class GlossaryService {
  static const _latin = {
    'a': 'а', 'b': 'б', 'c': 'ц', 'd': 'д', 'e': 'е', 'f': 'ф', 'g': 'г',
    'h': 'х', 'i': 'и', 'j': 'й', 'k': 'к', 'l': 'л', 'm': 'м', 'n': 'н',
    'o': 'о', 'p': 'п', 'q': 'к', 'r': 'р', 's': 'с', 't': 'т', 'u': 'у',
    'v': 'в', 'w': 'в', 'x': 'кс', 'y': 'й', 'z': 'з',
  };
  static const _vowels = 'аеёиоуыэюя';

  /// Применяет глоссарий к тексту. Возвращает исправленный текст.
  static String apply(String text, List<String> terms) {
    var out = text;
    for (final raw in terms) {
      final term = raw.trim();
      if (term.length < 3) continue;
      if (RegExp(r'[a-zA-Z]').hasMatch(term)) {
        out = _applyLatin(out, term);
      } else {
        out = _applyCyrillic(out, term);
      }
    }
    return out;
  }

  /// Термин с латиницей: строим «звучание» кириллицей и ищем близкие формы
  /// (гласные могут быть пропущены моделью, удвоения стягиваем).
  static String _applyLatin(String text, String term) {
    final buf = StringBuffer();
    String prev = '';
    for (final ch in term.toLowerCase().split('')) {
      if (ch == ' ' || ch == '-' || ch == ',') {
        buf.write(r'\s*');
        continue;
      }
      final mapped = _latin[ch];
      if (mapped == null) {
        buf.write(RegExp.escape(ch));
        continue;
      }
      for (final m in mapped.split('')) {
        if (m == prev) continue; // стягиваем удвоения
        prev = m;
        if (_vowels.contains(m)) {
          buf.write('$m?'); // гласная может быть не расслышана
        } else {
          buf.write(m);
        }
      }
    }
    final pattern = buf.toString();
    if (pattern.isEmpty) return text;
    try {
      final re = RegExp('(?<![а-яa-z0-9])$pattern(?![а-яa-z0-9])',
          caseSensitive: false);
      return text.replaceAll(re, term);
    } catch (_) {
      return text;
    }
  }

  /// Кириллический термин: правим падежные «хвосты» не трогаем — только
  /// точные вхождения в другом регистре/с пунктуацией рядом.
  static String _applyCyrillic(String text, String term) {
    try {
      final re = RegExp('(?<![а-яa-z0-9])${RegExp.escape(term)}(?![а-яa-z0-9])',
          caseSensitive: false);
      return text.replaceAll(re, term);
    } catch (_) {
      return text;
    }
  }
}
