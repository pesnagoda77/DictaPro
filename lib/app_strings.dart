// Локализованные строки DictaPro (tasks 052, 053).
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
    // Task 053: предупреждение перед расшифровкой длинной записи (>5 ч).
    // {d} — длительность записи («16 ч 40 мин»), {e} — оценка времени («≈ 3 ч»).
    'long_transcribe_title': {
      'ru': 'Длинная запись',
      'en': 'Long recording',
      'de': 'Lange Aufnahme',
      'it': 'Registrazione lunga',
    },
    'long_transcribe_body': {
      'ru': 'Запись {d}. Расшифровка может занять несколько часов (≈ {e}). Продолжить?',
      'en': 'Recording {d}. Transcription may take several hours (≈ {e}). Continue?',
      'de': 'Aufnahme {d}. Die Transkription kann mehrere Stunden dauern (≈ {e}). Fortfahren?',
      'it': 'Registrazione {d}. La trascrizione può richiedere diverse ore (≈ {e}). Continuare?',
    },
    'long_transcribe_continue': {
      'ru': 'Продолжить',
      'en': 'Continue',
      'de': 'Fortfahren',
      'it': 'Continuare',
    },
    'long_transcribe_cancel': {
      'ru': 'Отмена',
      'en': 'Cancel',
      'de': 'Abbrechen',
      'it': 'Annulla',
    },
    // Task 054: монетизация — лимит исчерпан → paywall.
    // {n} — дневной лимит минут, {u} — уже использовано сегодня.
    'limit_reached_title': {
      'ru': 'Лимит исчерпан',
      'en': 'Daily limit reached',
      'de': 'Tageslimit erreicht',
      'it': 'Limite giornaliero raggiunto',
    },
    'limit_reached_body': {
      'ru': 'Сегодня использовано {u} из {n} минут расшифровки.\n\n'
          'Полная версия — всё без лимитов: расшифровка на устройстве, итоги, теги, экспорт, поиск. Разовая покупка.',
      'en': 'You have used {u} of {n} transcription minutes today.\n\n'
          'Full version — everything without limits: on-device transcription, summaries, tags, export, search. One-time purchase.',
      'de': 'Heute wurden {u} von {n} Transkriptionsminuten verbraucht.\n\n'
          'Vollversion — alles ohne Limit: Transkription auf dem Gerät, Zusammenfassungen, Tags, Export, Suche. Einmaliger Kauf.',
      'it': 'Oggi hai usato {u} dei {n} minuti di trascrizione.\n\n'
          'Versione completa — tutto senza limiti: trascrizione sul dispositivo, riepiloghi, tag, esportazione, ricerca. Acquisto una tantum.',
    },
    'buy_full': {
      'ru': 'Купить полную версию',
      'en': 'Buy full version',
      'de': 'Vollversion kaufen',
      'it': 'Acquista versione completa',
    },
    'restore_purchase': {
      'ru': 'Восстановить покупку',
      'en': 'Restore purchase',
      'de': 'Kauf wiederherstellen',
      'it': 'Ripristina acquisto',
    },
    'store_unavailable': {
      'ru': 'Магазин сейчас недоступен. Проверьте интернет и попробуйте позже.',
      'en': 'The store is currently unavailable. Check your internet and try again later.',
      'de': 'Der Store ist derzeit nicht verfügbar. Prüfen Sie Ihre Internetverbindung.',
      'it': 'Lo store non è al momento disponibile. Controlla la connessione e riprova.',
    },
  };

  static String _langCode(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    return _dict.values.first.containsKey(lang) ? lang : 'ru';
  }

  static String _t(String key, BuildContext context) =>
      _dict[key]![_langCode(context)]!;

  /// `{placeholder}` в строке заменяются значениями из [params].
  static String _fmt(String s, Map<String, String> params) {
    var out = s;
    params.forEach((k, v) => out = out.replaceAll('{$k}', v));
    return out;
  }

  /// Слоган под «Голос → Текст» на сплэше (task 052).
  static String splashSlogan(BuildContext context) =>
      _t('splash_slogan', context);

  // ---------- Task 053: предупреждение о длинной расшифровке ----------

  static String longTranscribeTitle(BuildContext context) =>
      _t('long_transcribe_title', context);

  static String longTranscribeBody(
    BuildContext context, {
    required String duration,
    required String estimate,
  }) =>
      _fmt(_t('long_transcribe_body', context), {'d': duration, 'e': estimate});

  static String longTranscribeContinue(BuildContext context) =>
      _t('long_transcribe_continue', context);

  static String longTranscribeCancel(BuildContext context) =>
      _t('long_transcribe_cancel', context);

  // ---------- Task 054: монетизация ----------

  static String limitReachedTitle(BuildContext context) =>
      _t('limit_reached_title', context);

  static String limitReachedBody(
    BuildContext context, {
    required int used,
    required int limit,
  }) =>
      _fmt(_t('limit_reached_body', context),
          {'u': '$used', 'n': '$limit'});

  static String buyFull(BuildContext context) => _t('buy_full', context);

  static String restorePurchase(BuildContext context) =>
      _t('restore_purchase', context);

  static String storeUnavailable(BuildContext context) =>
      _t('store_unavailable', context);

  /// Человекочитаемая длительность: «16 ч 40 мин», «40 мин», «5 мин».
  static String humanDuration(int ms) {
    final totalMin = ms ~/ 60000;
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    if (h > 0 && m > 0) return '$h ч $m мин';
    if (h > 0) return '$h ч';
    return '$m мин';
  }

  /// Оценка времени расшифровки: «≈ 3 ч», «≈ 45 мин».
  /// Замерено на устройстве (task 053): N минут расшифровки на 1 час аудио.
  /// Коэффициент — из замера Claude (см. журнал), консервативный запас ×1.2.
  static const _kTranscribeMinutesPerAudioHour = 20.0; // PLACEHOLDER до замера

  static String transcribeEstimate(int audioMs) {
    final audioHours = audioMs / 3600000.0;
    final estMin = (audioHours * _kTranscribeMinutesPerAudioHour * 1.2).round();
    final h = estMin ~/ 60;
    final m = estMin % 60;
    if (h > 0 && m > 0) return '≈ $h ч $m мин';
    if (h > 0) return '≈ $h ч';
    return '≈ $m мин';
  }
}
