import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Настройка «Локальная чистка текста» (по умолчанию ВКЛ).
class LocalTextCleanupSettings {
  static const _key = 'local_cleanup_enabled';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? true;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}

/// «Горячие слова» пользователя: последние введённые термины записи.
/// Сохраняем, чтобы предлагать повторно (чипы на экране записи).
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

/// Строго локальная (без сети) доводка офлайн-транскрипта VOSK:
/// 1) русские числительные → цифры (в т.ч. «целых/десятых/сотых/тысячных»,
///    «процент» → %, малые единицы измерения → сокращения);
/// 2) пробелы и пунктуация (без дублирования PunctuationService).
/// Ничего не «додумывается по смыслу» — только детерминированные замены.
class LocalTextCleanup {
  LocalTextCleanup._();

  // --- Словари форм (ё уже нормализована к е) ---

  static const Map<String, int> _cardinal = {
    // единицы (им. + род./вин. падежи)
    'один': 1, 'одна': 1, 'одно': 1, 'одного': 1, 'одной': 1, 'одну': 1,
    'два': 2, 'две': 2, 'двух': 2,
    'три': 3, 'трёх': 3, 'трех': 3,
    'четыре': 4, 'четырёх': 4, 'четырех': 4,
    'пять': 5, 'пяти': 5,
    'шесть': 6, 'шести': 6,
    'семь': 7, 'семи': 7,
    'восемь': 8, 'восьми': 8,
    'девять': 9, 'девяти': 9,
    'десять': 10, 'десяти': 10,
    'одиннадцать': 11, 'одиннадцати': 11,
    'двенадцать': 12, 'двенадцати': 12,
    'тринадцать': 13, 'тринадцати': 13,
    'четырнадцать': 14, 'четырнадцати': 14,
    'пятнадцать': 15, 'пятнадцати': 15,
    'шестнадцать': 16, 'шестнадцати': 16,
    'семнадцать': 17, 'семнадцати': 17,
    'восемнадцать': 18, 'восемнадцати': 18,
    'девятнадцать': 19, 'девятнадцати': 19,
    // десятки
    'двадцать': 20, 'двадцати': 20,
    'тридцать': 30, 'тридцати': 30,
    'сорок': 40, 'сорока': 40,
    'пятьдесят': 50, 'пятидесяти': 50,
    'шестьдесят': 60, 'шестидесяти': 60,
    'семьдесят': 70, 'семидесяти': 70,
    'восемьдесят': 80, 'восьмидесяти': 80,
    'девяносто': 90, 'девяноста': 90,
    // сотни
    'сто': 100, 'ста': 100,
    'двести': 200, 'двухсот': 200,
    'триста': 300, 'трёхсот': 300, 'трехсот': 300,
    'четыреста': 400, 'четырёхсот': 400, 'четырехсот': 400,
    'пятьсот': 500, 'пятисот': 500,
    'шестьсот': 600, 'шестисот': 600,
    'семьсот': 700, 'семисот': 700,
    'восемьсот': 800, 'восьмисот': 800,
    'девятьсот': 900, 'девятисот': 900,
  };

  static const Set<String> _thousand = {
    'тысяча', 'тысячи', 'тысяч', 'тысяче', 'тысячу', 'тысячей', 'тысячах',
  };

  /// «десятых/сотых/тысячных» → число знаков после запятой.
  static const Map<String, int> _scale = {
    'десятых': 1, 'десятая': 1,
    'сотых': 2, 'сотая': 2,
    'тысячных': 3, 'тысячная': 3,
  };

  static const Set<String> _whole = {'целых', 'целая', 'целой', 'целое'};

  static const Set<String> _comma = {'запятая', 'запятой', 'запятою'};

  static const Set<String> _percent = {
    'процент', 'процента', 'процентов', 'проценту', 'процентом',
    'проценте', 'процентами',
  };

  static const Map<String, int> _ordinalUnit = {
    'первый': 1, 'первого': 1, 'первом': 1,
    'второй': 2, 'второго': 2, 'втором': 2,
    'третий': 3, 'третьего': 3, 'третьем': 3,
    'четвертый': 4, 'четвертого': 4, 'четвертом': 4,
    'пятый': 5, 'пятого': 5, 'пятом': 5,
    'шестой': 6, 'шестого': 6, 'шестом': 6,
    'седьмой': 7, 'седьмого': 7, 'седьмом': 7,
    'восьмой': 8, 'восьмого': 8, 'восьмом': 8,
    'девятый': 9, 'девятого': 9, 'девятом': 9,
    'десятый': 10, 'десятого': 10, 'десятом': 10,
    'одиннадцатый': 11, 'одиннадцатого': 11,
    'двенадцатый': 12, 'двенадцатого': 12,
    'тринадцатый': 13, 'тринадцатого': 13,
    'четырнадцатый': 14, 'четырнадцатого': 14,
    'пятнадцатый': 15, 'пятнадцатого': 15,
    'шестнадцатый': 16, 'шестнадцатого': 16,
    'семнадцатый': 17, 'семнадцатого': 17,
    'восемнадцатый': 18, 'восемнадцатого': 18,
    'девятнадцатый': 19, 'девятнадцатого': 19,
  };

  static const Map<String, int> _ordinalTens = {
    'двадцатый': 20, 'двадцатого': 20,
    'тридцатый': 30, 'тридцатого': 30,
    'сороковой': 40, 'сорокового': 40,
    'пятидесятый': 50, 'пятидесятого': 50,
    'шестидесятый': 60, 'шестидесятого': 60,
    'семидесятый': 70, 'семидесятого': 70,
    'восьмидесятый': 80, 'восьмидесятого': 80,
    'девяностый': 90, 'девяностого': 90,
  };

  static const Map<String, String> _unitShort = {
    'миллиграмм': 'мг', 'миллиграмма': 'мг', 'миллиграммов': 'мг',
    'грамм': 'г', 'грамма': 'г', 'граммов': 'г',
    'килограмм': 'кг', 'килограмма': 'кг', 'килограммов': 'кг',
    'миллилитр': 'мл', 'миллилитра': 'мл', 'миллилитров': 'мл',
    'литр': 'л', 'литра': 'л', 'литров': 'л',
  };

  static const Set<String> _yearWord = {
    'год', 'года', 'году', 'годом', 'годе',
  };

  static final RegExp _letters = RegExp(r'^[A-Za-zА-Яа-я]+$');

  static String _norm(String w) => w.toLowerCase().replaceAll('ё', 'е');

  /// Возвращает «чистое» слово (без пунктуации по краям) или null.
  static String? _core(String token) {
    var s = token;
    while (s.isNotEmpty && !_letters.hasMatch(s[0]) &&
        !RegExp(r'[0-9]').hasMatch(s[0])) {
      s = s.substring(1);
    }
    while (s.isNotEmpty &&
        !_letters.hasMatch(s[s.length - 1]) &&
        !RegExp(r'[0-9]').hasMatch(s[s.length - 1])) {
      s = s.substring(0, s.length - 1);
    }
    return s.isEmpty ? null : s;
  }

  static bool _isNumeralWord(String core) {
    final c = _norm(core);
    return _cardinal.containsKey(c) ||
        _thousand.contains(c) ||
        _scale.containsKey(c) ||
        _whole.contains(c) ||
        _comma.contains(c) ||
        _percent.contains(c) ||
        _ordinalUnit.containsKey(c) ||
        _ordinalTens.containsKey(c) ||
        _unitShort.containsKey(c);
  }

  /// Значение кардинального фрагмента (без порядковых и служебных слов).
  static int _evalCardinal(Iterable<String> cores) {
    var total = 0;
    var cur = 0;
    for (final raw in cores) {
      final c = _norm(raw);
      if (_thousand.contains(c)) {
        total += (cur == 0 ? 1 : cur) * 1000;
        cur = 0;
      } else {
        cur += _cardinal[c] ?? 0;
      }
    }
    return total + cur;
  }

  /// Главная точка входа.
  static String cleanup(String text) {
    if (text.trim().isEmpty) return text;
    final tokens = text.split(RegExp(r'\s+'));
    final out = <String>[];
    var i = 0;
    while (i < tokens.length) {
      final core = _core(tokens[i]);
      if (core == null || !_isNumeralWord(core)) {
        out.add(tokens[i]);
        i++;
        continue;
      }
      // Собираем непрерывную фразу из числительных (лимит — 14 слов)
      var j = i;
      final phrase = <String>[];
      while (j < tokens.length && phrase.length < 14) {
        final c = _core(tokens[j]);
        if (c == null || !_isNumeralWord(c)) break;
        phrase.add(c);
        j++;
      }
      final conv = _convert(phrase, tokens, j);
      if (conv == null) {
        out.add(tokens[i]);
        i++;
      } else {
        out.add(conv.$1);
        i = conv.$2;
      }
    }
    return _polish(out.join(' '));
  }

  /// Пробелы/пунктуация (без лишнего — заглавные делает PunctuationService).
  static String _polish(String s) {
    s = s.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
    s = s.replaceAll(RegExp(r'\s+([,.;:!?])'), r'$1');
    return s.trim();
  }

  /// Пытается превратить фразу числительных в цифры.
  /// Возвращает (замена, индекс следующего токена) или null — не трогаем.
  static (String, int)? _convert(List<String> p, List<String> tokens, int j) {
    final hasThousand = p.any(_thousand.contains);
    final percentIdx = p.indexWhere(_percent.contains);
    final wholeIdx = p.indexWhere(_whole.contains);
    final scaleIdx = p.indexWhere(_scale.containsKey);
    final commaIdx = p.indexWhere(_comma.contains);
    final unitIdx = p.indexWhere(_unitShort.containsKey);
    final firstOrdinal = p.indexWhere(
        (c) => _ordinalUnit.containsKey(c) || _ordinalTens.containsKey(c));
    final lastIsOrdinal = p.isNotEmpty &&
        (_ordinalUnit.containsKey(p.last) || _ordinalTens.containsKey(p.last));

    final trail = _trailing(tokens[j - 1]);

    // «запятая шестьдесят четыре сотых» → «,64»
    if (commaIdx >= 0 && commaIdx == 0 && scaleIdx > 0) {
      final frac = _evalCardinal(p.sublist(1, scaleIdx));
      final scale = _scale[p[scaleIdx]]!;
      return (',${frac.toString().padLeft(scale, '0')}$trail', j);
    }

    // «восемьдесят восемь целых шестьдесят четыре сотых процента» → «88,64%»
    if (wholeIdx > 0 && scaleIdx > wholeIdx) {
      final intPart = _evalCardinal(p.sublist(0, wholeIdx));
      final frac = _evalCardinal(p.sublist(wholeIdx + 1, scaleIdx));
      final scale = _scale[p[scaleIdx]]!;
      var res = '$intPart,${frac.toString().padLeft(scale, '0')}';
      if (percentIdx > scaleIdx) res += '%';
      if (unitIdx > scaleIdx) res += ' ${_unitShort[p[unitIdx]]}';
      return ('$res$trail', j);
    }

    // «восемьдесят восемь запятая шестьдесят четыре процента» → «88,64%»
    if (commaIdx > 0) {
      final intPart = _evalCardinal(p.sublist(0, commaIdx));
      final rest = <String>[];
      for (var k = commaIdx + 1; k < p.length; k++) {
        if (_percent.contains(p[k]) || _unitShort.containsKey(p[k])) {
          continue;
        }
        rest.add(p[k]);
      }
      final frac = _evalCardinal(rest);
      var res = '$intPart,$frac';
      if (percentIdx > commaIdx) res += '%';
      if (unitIdx > commaIdx) res += ' ${_unitShort[p[unitIdx]]}';
      return ('$res$trail', j);
    }

    // «две тысячи двадцать четвёртый год» → «2024 год»
    if (lastIsOrdinal && firstOrdinal == p.length - 1) {
      final value = _evalMixedOrdinal(p);
      if (j < tokens.length &&
          _yearWord.contains(_norm(_core(tokens[j]) ?? ''))) {
        // Падеж сохраняем: «в 2024 году», «2024 год»
        final yearCore = _norm(_core(tokens[j])!);
        return ('$value $yearCore$trail', j + 1);
      }
      if (value >= 10) return ('$value$trail', j);
      return null;
    }

    // «… процента» → «…%»
    if (percentIdx == p.length - 1 && percentIdx > 0) {
      final value = _evalCardinal(p.sublist(0, percentIdx));
      if (value >= 10 || hasThousand) return ('$value%$trail', j);
      return null;
    }

    // «… миллиграмма» → «… мг»
    if (unitIdx == p.length - 1 && unitIdx > 0) {
      final value = _evalCardinal(p.sublist(0, unitIdx));
      if (value >= 10 || hasThousand) {
        return ('$value ${_unitShort[p[unitIdx]]}$trail', j);
      }
      return null;
    }

    // Просто большое число (или с тысячами) — в цифры.
    if (firstOrdinal == -1 && wholeIdx == -1 && commaIdx == -1) {
      final value = _evalCardinal(p);
      if (value >= 10 || hasThousand) return ('$value$trail', j);
    }
    return null;
  }

  /// Кардиналы + последний порядковый («двадцать четвёртый» → 24).
  static int _evalMixedOrdinal(List<String> p) {
    var total = 0;
    var cur = 0;
    for (var k = 0; k < p.length; k++) {
      final c = _norm(p[k]);
      if (_thousand.contains(c)) {
        total += (cur == 0 ? 1 : cur) * 1000;
        cur = 0;
      } else if (k == p.length - 1) {
        cur += _ordinalUnit[c] ?? _ordinalTens[c] ?? _cardinal[c] ?? 0;
      } else {
        cur += _cardinal[c] ?? 0;
      }
    }
    return total + cur;
  }

  static String _trailing(String token) {
    var k = token.length;
    while (k > 0 &&
        !_letters.hasMatch(token[k - 1]) &&
        !RegExp(r'[0-9]').hasMatch(token[k - 1])) {
      k--;
    }
    return token.substring(k);
  }
}
