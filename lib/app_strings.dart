// Локализованные строки DictaPro (task 052).
// Полноценной i18n-инфраструктуры в проекте нет — UI исторически русский.
// Здесь компактный словарь для строк, которые ТЗ требует на 4 языках
// (ru/en/de/it). Язык берём из системной локали, дефолт — русский.
// Смысловой слоган линейки: запись и распознавание идут на устройстве,
// данные никуда не отправляются.
import 'package:flutter/widgets.dart';

class AppStrings {
  AppStrings._();

  /// Словарь: ключ → {код языка: строка}. Русский — обязательный fallback.
  static const _dict = <String, Map<String, String>>{
    'splash_slogan': {
      'ru': 'Не покидая телефон',
      'en': 'Never leaves your phone',
      'de': 'Verlässt dein Handy nie',
      'it': 'Non lascia mai il telefono',
    },
  };

  static String _langCode(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    return _dict.values.first.containsKey(lang) ? lang : 'ru';
  }

  /// Слоган под «Голос → Текст» на сплэше (task 052).
  static String splashSlogan(BuildContext context) =>
      _dict['splash_slogan']![_langCode(context)]!;
}
