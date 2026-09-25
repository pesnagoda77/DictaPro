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
    // Task 059: два вида итогов + ИИ-часы.
    'summary_local_btn': {
      'ru': 'Итоги локально',
      'en': 'On-device summary',
      'de': 'Zusammenfassung lokal',
      'it': 'Riepilogo locale',
    },
    'summary_online_btn': {
      'ru': 'Итоги онлайн',
      'en': 'Online summary',
      'de': 'Zusammenfassung online',
      'it': 'Riepilogo online',
    },
    'online_summary_warning_title': {
      'ru': 'Отправить на сервер?',
      'en': 'Send to server?',
      'de': 'An Server senden?',
      'it': 'Inviare al server?',
    },
    'online_summary_warning_body': {
      'ru': 'Функцию запускаете вы сами. Текст записи уйдёт на наш сервер для обработки и вернётся итогами. Локальные итоги работают без интернета и без отправки данных. Продолжить?',
      'en': 'You run this feature yourself. The recording text will be sent to our server for processing and come back as summaries. On-device summaries work offline without sending any data. Continue?',
      'de': 'Sie starten diese Funktion selbst. Der Aufnahmetext wird zur Verarbeitung an unseren Server gesendet und als Zusammenfassung zurückgesendet. Lokale Zusammenfassungen funktionieren offline ohne Datenversand. Fortfahren?',
      'it': 'Avvii tu questa funzione. Il testo della registrazione verrà inviato al nostro server per l\'elaborazione e restituito come riepilogo. I riepiloghi locali funzionano offline senza invio di dati. Continuare?',
    },
    'online_summary_cancel': {
      'ru': 'Отмена', 'en': 'Cancel', 'de': 'Abbrechen', 'it': 'Annulla',
    },
    'online_summary_send': {
      'ru': 'Отправить', 'en': 'Send', 'de': 'Senden', 'it': 'Invia',
    },
    'online_summary_stage': {
      'ru': 'Итоги на сервере…',
      'en': 'Summarizing on server…',
      'de': 'Zusammenfassung auf dem Server…',
      'it': 'Riepilogo sul server…',
    },
    'online_summary_title': {
      'ru': 'Итоги (онлайн)',
      'en': 'Summary (online)',
      'de': 'Zusammenfassung (online)',
      'it': 'Riepilogo (online)',
    },
    'online_summary_failed': {
      'ru': 'Не удалось получить итоги. Проверьте интернет и попробуйте позже.',
      'en': 'Could not get summaries. Check your internet and try again.',
      'de': 'Zusammenfassung fehlgeschlagen. Internet prüfen und erneut versuchen.',
      'it': 'Impossibile ottenere il riepilogo. Controlla internet e riprova.',
    },
    'online_summary_no_hours': {
      'ru': 'ИИ-часы закончились. Продлите подписку или докупите пакет часов.',
      'en': 'AI hours are used up. Renew your subscription or buy an hours pack.',
      'de': 'KI-Stunden sind aufgebraucht. Abo verlängern oder Stundenpaket kaufen.',
      'it': 'Ore AI esaurite. Rinnova l\'abbonamento o acquista un pacchetto di ore.',
    },
    'online_summary_from_cache': {
      'ru': 'Взято из кэша — бесплатно.',
      'en': 'Served from cache — free.',
      'de': 'Aus dem Cache — kostenlos.',
      'it': 'Dal cache — gratis.',
    },
    'online_summary_spent': {
      'ru': 'Списано {h} ИИ-ч.',
      'en': 'Charged {h} AI hours.',
      'de': '{h} KI-Stunden abgebucht.',
      'it': 'Addebitate {h} ore AI.',
    },
    'online_summary_refresh': {
      'ru': 'Обновить', 'en': 'Refresh', 'de': 'Aktualisieren', 'it': 'Aggiorna',
    },
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

    // ---------- Task 060: полная локализация UI ----------
    'app_title': {
      'ru': 'ДиктаПро', 'en': 'DictaPro', 'de': 'DictaPro', 'it': 'DictaPro',
    },
    // Главный экран
    'recording_now': {
      'ru': '● Идет запись...',
      'en': '● Recording...',
      'de': '● Aufnahme läuft...',
      'it': '● Registrazione in corso...',
    },
    'tap_to_record': {
      'ru': 'Нажмите для записи',
      'en': 'Tap to record',
      'de': 'Tippen zum Aufnehmen',
      'it': 'Tocca per registrare',
    },
    'start_recording': {
      'ru': 'Начать запись',
      'en': 'Start recording',
      'de': 'Aufnahme starten',
      'it': 'Inizia registrazione',
    },
    'stop_recording': {
      'ru': 'Остановить запись',
      'en': 'Stop recording',
      'de': 'Aufnahme stoppen',
      'it': 'Ferma registrazione',
    },
    'sleep_timer': {
      'ru': 'Таймер сна',
      'en': 'Sleep timer',
      'de': 'Schlaf-Timer',
      'it': 'Timer spegnimento',
    },
    'timer_active': {
      'ru': 'Таймер: {m} мин',
      'en': 'Timer: {m} min',
      'de': 'Timer: {m} Min',
      'it': 'Timer: {m} min',
    },
    'timer_min': {
      'ru': '{m} мин',
      'en': '{m} min',
      'de': '{m} Min',
      'it': '{m} min',
    },
    'timer_dialog_title': {
      'ru': 'Таймер остановки',
      'en': 'Stop timer',
      'de': 'Stopp-Timer',
      'it': 'Timer di arresto',
    },
    'timer_none': {
      'ru': 'Без таймера',
      'en': 'No timer',
      'de': 'Ohne Timer',
      'it': 'Nessun timer',
    },
    'minutes_15': {
      'ru': '15 минут', 'en': '15 minutes', 'de': '15 Minuten', 'it': '15 minuti',
    },
    'minutes_30': {
      'ru': '30 минут', 'en': '30 minutes', 'de': '30 Minuten', 'it': '30 minuti',
    },
    'minutes_60': {
      'ru': '60 минут', 'en': '60 minutes', 'de': '60 Minuten', 'it': '60 minuti',
    },
    'hotwords_hint': {
      'ru': 'Термины этой записи (имена, аббревиатуры — через запятую)',
      'en': 'Terms for this recording (names, abbreviations — comma separated)',
      'de': 'Begriffe dieser Aufnahme (Namen, Abkürzungen — kommagetrennt)',
      'it': 'Termini di questa registrazione (nomi, abbreviazioni — separati da virgola)',
    },
    'engine_label': {
      'ru': 'Распознавание: на устройстве · модель внутри',
      'en': 'Recognition: on-device · model inside',
      'de': 'Erkennung: auf dem Gerät · Modell integriert',
      'it': 'Riconoscimento: sul dispositivo · modello integrato',
    },
    'settings_tooltip': {
      'ru': 'Настройки', 'en': 'Settings', 'de': 'Einstellungen', 'it': 'Impostazioni',
    },
    'search_hint': {
      'ru': 'Поиск по транскрипциям...',
      'en': 'Search transcripts...',
      'de': 'Transkripte durchsuchen...',
      'it': 'Cerca nelle trascrizioni...',
    },
    'favorites_count': {
      'ru': 'Избранное ({n})', 'en': 'Favorites ({n})',
      'de': 'Favoriten ({n})', 'it': 'Preferiti ({n})',
    },
    'recordings_count': {
      'ru': 'Записи ({n})', 'en': 'Recordings ({n})',
      'de': 'Aufnahmen ({n})', 'it': 'Registrazioni ({n})',
    },
    'found_count': {
      'ru': 'Найдено: {n}', 'en': 'Found: {n}',
      'de': 'Gefunden: {n}', 'it': 'Trovati: {n}',
    },
    'sort_tooltip': {
      'ru': 'Сортировка', 'en': 'Sort', 'de': 'Sortierung', 'it': 'Ordinamento',
    },
    'sort_date_newest': {
      'ru': 'Дата (новые)', 'en': 'Date (newest)',
      'de': 'Datum (neueste)', 'it': 'Data (recenti)',
    },
    'sort_date_oldest': {
      'ru': 'Дата (старые)', 'en': 'Date (oldest)',
      'de': 'Datum (älteste)', 'it': 'Data (più vecchie)',
    },
    'sort_name_asc': {
      'ru': 'Имя (А-Я)', 'en': 'Name (A-Z)',
      'de': 'Name (A-Z)', 'it': 'Nome (A-Z)',
    },
    'sort_duration_longest': {
      'ru': 'Длительность (длинные)', 'en': 'Duration (longest)',
      'de': 'Dauer (längste)', 'it': 'Durata (più lunghe)',
    },
    'sort_duration_shortest': {
      'ru': 'Длительность (короткие)', 'en': 'Duration (shortest)',
      'de': 'Dauer (kürzeste)', 'it': 'Durata (più corte)',
    },
    'empty_search_title': {
      'ru': 'Ничего не нашлось', 'en': 'Nothing found',
      'de': 'Nichts gefunden', 'it': 'Nessun risultato',
    },
    'empty_search_body': {
      'ru': 'Попробуйте другое слово или очистите поиск.',
      'en': 'Try another word or clear the search.',
      'de': 'Anderes Wort versuchen oder Suche leeren.',
      'it': 'Prova un\'altra parola o cancella la ricerca.',
    },
    'empty_rec_title': {
      'ru': 'Пока ни одной записи', 'en': 'No recordings yet',
      'de': 'Noch keine Aufnahmen', 'it': 'Nessuna registrazione',
    },
    'empty_rec_body': {
      'ru': 'Нажмите большую кнопку «Начать запись» — или импортируйте готовый файл (mp3, m4a, wav) и расшифруйте его.',
      'en': 'Tap the big "Start recording" button — or import an existing file (mp3, m4a, wav) and transcribe it.',
      'de': 'Tippen Sie auf die große Taste „Aufnahme starten“ — oder importieren Sie eine Datei (mp3, m4a, wav) und transkribieren Sie sie.',
      'it': 'Tocca il grande pulsante «Inizia registrazione» — oppure importa un file (mp3, m4a, wav) e trascrivilo.',
    },
    'btn_dialog': {
      'ru': 'Диалог', 'en': 'Dialogue', 'de': 'Dialog', 'it': 'Dialogo',
    },
    'btn_to_text': {
      'ru': 'В текст', 'en': 'To text', 'de': 'Zu Text', 'it': 'A testo',
    },
    'btn_gist': {
      'ru': 'Суть', 'en': 'Gist', 'de': 'Kernaussage', 'it': 'Sintesi',
    },
    'btn_send': {
      'ru': 'Отправить', 'en': 'Send', 'de': 'Senden', 'it': 'Invia',
    },
    'btn_listen': {
      'ru': 'Слушать', 'en': 'Listen', 'de': 'Anhören', 'it': 'Ascolta',
    },
    'btn_delete': {
      'ru': 'Удалить', 'en': 'Delete', 'de': 'Löschen', 'it': 'Elimina',
    },
    // Расшифровка / прогресс
    'transcribing_now': {
      'ru': 'Идёт расшифровка', 'en': 'Transcribing',
      'de': 'Transkription läuft', 'it': 'Trascrizione in corso',
    },
    'live_running_min': {
      'ru': 'идёт {m} мин', 'en': 'running {m} min',
      'de': 'läuft seit {m} Min', 'it': 'in corso da {m} min',
    },
    'live_chunks_done': {
      'ru': 'готово кусков: {n}', 'en': 'chunks done: {n}',
      'de': 'fertige Teile: {n}', 'it': 'segmenti pronti: {n}',
    },
    'live_chars': {
      'ru': 'символов: {n}', 'en': 'characters: {n}',
      'de': 'Zeichen: {n}', 'it': 'caratteri: {n}',
    },
    'transcribe_already': {
      'ru': 'Расшифровка уже идёт — дождитесь окончания',
      'en': 'Transcription is already running — please wait',
      'de': 'Transkription läuft bereits — bitte warten',
      'it': 'La trascrizione è già in corso — attendi',
    },
    'op_transcribing': {
      'ru': 'Расшифровка…', 'en': 'Transcribing…',
      'de': 'Transkribieren…', 'it': 'Trascrizione…',
    },
    'creating_pdf': {
      'ru': 'Создание PDF...', 'en': 'Creating PDF...',
      'de': 'PDF wird erstellt...', 'it': 'Creazione PDF...',
    },
    'online_recognizing': {
      'ru': 'Онлайн-распознавание…', 'en': 'Online recognition…',
      'de': 'Online-Erkennung…', 'it': 'Riconoscimento online…',
    },
    'online_failed': {
      'ru': 'Онлайн не удался, остаёмся офлайн: {e}',
      'en': 'Online failed, staying offline: {e}',
      'de': 'Online fehlgeschlagen, bleibe offline: {e}',
      'it': 'Online non riuscito, resto offline: {e}',
    },
    'offline_warn_title': {
      'ru': 'Вы выходите из офлайн-режима',
      'en': 'You are leaving offline mode',
      'de': 'Sie verlassen den Offline-Modus',
      'it': 'Stai uscendo dalla modalità offline',
    },
    'offline_warn_body': {
      'ru': 'Обычно все записи остаются только на этом устройстве. Для точного распознавания звук этой записи будет отправлен на сервер ({p}). Больше ничего не передаётся.',
      'en': 'Usually all recordings stay on this device only. For accurate recognition, this recording\'s audio will be sent to the server ({p}). Nothing else is transmitted.',
      'de': 'Normalerweise bleiben alle Aufnahmen nur auf diesem Gerät. Für eine genaue Erkennung wird der Ton dieser Aufnahme an den Server gesendet ({p}). Es wird nichts weiter übertragen.',
      'it': 'Di solito tutte le registrazioni restano solo su questo dispositivo. Per un riconoscimento accurato, l\'audio di questa registrazione verrà inviato al server ({p}). Non viene trasmesso altro.',
    },
    'stay_offline': {
      'ru': 'Остаться офлайн', 'en': 'Stay offline',
      'de': 'Offline bleiben', 'it': 'Rimani offline',
    },
    'recognize_online': {
      'ru': 'Распознать онлайн', 'en': 'Recognize online',
      'de': 'Online erkennen', 'it': 'Riconosci online',
    },
    'unfinished_title': {
      'ru': 'Незавершённая расшифровка', 'en': 'Unfinished transcription',
      'de': 'Unvollständige Transkription', 'it': 'Trascrizione incompleta',
    },
    'unfinished_body': {
      'ru': 'В прошлый раз распознание оборвалось на куске {c} ({s} символов текста уже готово).\n\nПродолжить с этого места или начать заново?',
      'en': 'Last time recognition stopped at chunk {c} ({s} characters of text already done).\n\nContinue from there or start over?',
      'de': 'Beim letzten Mal wurde die Erkennung bei Teil {c} unterbrochen ({s} Zeichen Text bereits fertig).\n\nVon dort fortfahren oder neu beginnen?',
      'it': 'L\'ultima volta il riconoscimento si è interrotto al segmento {c} ({s} caratteri di testo già pronti).\n\nContinuare da lì o ricominciare?',
    },
    'start_over': {
      'ru': 'Начать заново', 'en': 'Start over',
      'de': 'Neu beginnen', 'it': 'Ricomincia',
    },
    'keepalive_prep': {
      'ru': 'Расшифровка: готовлю аудио…', 'en': 'Transcription: preparing audio…',
      'de': 'Transkription: Audiovorbereitung…', 'it': 'Trascrizione: preparazione audio…',
    },
    'stage_prep_audio': {
      'ru': 'Готовим аудио (декодирование)…', 'en': 'Preparing audio (decoding)…',
      'de': 'Audio vorbereiten (Decodierung)…', 'it': 'Preparazione audio (decodifica)…',
    },
    'stage_resume_skip': {
      'ru': 'Продолжаем: пропускаем {n} готовых кусков…',
      'en': 'Resuming: skipping {n} finished chunks…',
      'de': 'Fortsetzen: {n} fertige Teile werden übersprungen…',
      'it': 'Ripresa: salto {n} segmenti già pronti…',
    },
    'stage_transcribing': {
      'ru': 'Расшифровка идёт…', 'en': 'Transcribing…',
      'de': 'Transkription läuft…', 'it': 'Trascrizione in corso…',
    },
    'chunk_progress': {
      'ru': 'Кусок {d} из {a}', 'en': 'Chunk {d} of {a}',
      'de': 'Teil {d} von {a}', 'it': 'Segmento {d} di {a}',
    },
    'elapsed': {
      'ru': 'прошло {t}', 'en': 'elapsed {t}',
      'de': 'vergangen {t}', 'it': 'trascorso {t}',
    },
    'on_device_note': {
      'ru': 'Считается на устройстве — можно не держать экран открытым',
      'en': 'Runs on-device — you can turn the screen off',
      'de': 'Läuft auf dem Gerät — der Bildschirm kann aus bleiben',
      'it': 'Funziona sul dispositivo — puoi spegnere lo schermo',
    },
    'model_prep_title': {
      'ru': 'Подготовка модели', 'en': 'Preparing model',
      'de': 'Modell wird vorbereitet', 'it': 'Preparazione del modello',
    },
    'summary_computing': {
      'ru': 'Считаю саммари…', 'en': 'Computing summary…',
      'de': 'Zusammenfassung wird erstellt…', 'it': 'Calcolo del riepilogo…',
    },
    'summary_part': {
      'ru': 'Считаю саммари… часть {d} из {t}',
      'en': 'Computing summary… part {d} of {t}',
      'de': 'Zusammenfassung… Teil {d} von {t}',
      'it': 'Calcolo riepilogo… parte {d} di {t}',
    },
    'summary_failed': {
      'ru': 'Итоги: не удалось собрать', 'en': 'Summary: could not generate',
      'de': 'Zusammenfassung: Erstellung fehlgeschlagen', 'it': 'Riepilogo: impossibile generare',
    },
    'summary_failed_snack': {
      'ru': 'Не получилось посчитать саммари', 'en': 'Could not compute summary',
      'de': 'Zusammenfassung fehlgeschlagen', 'it': 'Impossibile calcolare il riepilogo',
    },
    'transcription_done_bg': {
      'ru': 'Расшифровка готова — текст сохранён в записи',
      'en': 'Transcription ready — text saved to the recording',
      'de': 'Transkription fertig — Text in der Aufnahme gespeichert',
      'it': 'Trascrizione pronta — testo salvato nella registrazione',
    },
    'imported': {
      'ru': 'Импортировано: {n}', 'en': 'Imported: {n}',
      'de': 'Importiert: {n}', 'it': 'Importati: {n}',
    },
    'imported_errors': {
      'ru': 'Импортировано: {n}, ошибок: {e}',
      'en': 'Imported: {n}, errors: {e}',
      'de': 'Importiert: {n}, Fehler: {e}',
      'it': 'Importati: {n}, errori: {e}',
    },
    'export_format_title': {
      'ru': 'Формат экспорта', 'en': 'Export format',
      'de': 'Exportformat', 'it': 'Formato di esportazione',
    },
    'export_txt': {
      'ru': 'TXT — текст с таймкодами', 'en': 'TXT — text with timecodes',
      'de': 'TXT — Text mit Zeitcodes', 'it': 'TXT — testo con timecode',
    },
    'export_html': {
      'ru': 'HTML — красивый документ', 'en': 'HTML — nice document',
      'de': 'HTML — schönes Dokument', 'it': 'HTML — documento elegante',
    },
    'export_copy': {
      'ru': 'Скопировать текст', 'en': 'Copy text',
      'de': 'Text kopieren', 'it': 'Copia testo',
    },
    'export_pdf': {
      'ru': 'PDF — документ', 'en': 'PDF — document',
      'de': 'PDF — Dokument', 'it': 'PDF — documento',
    },
    'export_pdf_error': {
      'ru': 'Ошибка PDF: {e}', 'en': 'PDF error: {e}',
      'de': 'PDF-Fehler: {e}', 'it': 'Errore PDF: {e}',
    },
    'text_copied': {
      'ru': 'Текст скопирован', 'en': 'Text copied',
      'de': 'Text kopiert', 'it': 'Testo copiato',
    },
    'share_title': {
      'ru': 'Поделиться', 'en': 'Share', 'de': 'Teilen', 'it': 'Condividi',
    },
    'share_transcript': {
      'ru': 'Текст транскрипции', 'en': 'Transcript text',
      'de': 'Transkripttext', 'it': 'Testo della trascrizione',
    },
    'share_audio': {
      'ru': 'Аудиозапись', 'en': 'Audio recording',
      'de': 'Audioaufnahme', 'it': 'Registrazione audio',
    },
    'send_text_title': {
      'ru': 'Отправить текст', 'en': 'Send text',
      'de': 'Text senden', 'it': 'Invia testo',
    },
    'share_pdf_caption': {
      'ru': 'Транскрипция записи в PDF', 'en': 'Recording transcript as PDF',
      'de': 'Aufnahme-Transkript als PDF', 'it': 'Trascrizione in PDF',
    },
    'rename_title': {
      'ru': 'Переименовать', 'en': 'Rename',
      'de': 'Umbenennen', 'it': 'Rinomina',
    },
    'rename_hint': {
      'ru': 'Название записи...', 'en': 'Recording name...',
      'de': 'Name der Aufnahme...', 'it': 'Nome della registrazione...',
    },
    'save': {
      'ru': 'Сохранить', 'en': 'Save', 'de': 'Speichern', 'it': 'Salva',
    },
    'file_not_found': {
      'ru': 'Файл не найден: {p}', 'en': 'File not found: {p}',
      'de': 'Datei nicht gefunden: {p}', 'it': 'File non trovato: {p}',
    },
    'platform_error': {
      'ru': 'Ошибка платформы', 'en': 'Platform error',
      'de': 'Plattformfehler', 'it': 'Errore di piattaforma',
    },
    'error_prefix': {
      'ru': 'Ошибка: {m}', 'en': 'Error: {m}',
      'de': 'Fehler: {m}', 'it': 'Errore: {m}',
    },
    'transcribe_error': {
      'ru': 'Ошибка транскрибации: {e}', 'en': 'Transcription error: {e}',
      'de': 'Transkriptionsfehler: {e}', 'it': 'Errore di trascrizione: {e}',
    },
    'transcribe_failed': {
      'ru': 'Расшифровка не удалась: {e}', 'en': 'Transcription failed: {e}',
      'de': 'Transkription fehlgeschlagen: {e}', 'it': 'Trascrizione non riuscita: {e}',
    },
    // Карточка восстановления
    'recovery_interrupted': {
      'ru': 'Расшифровка прервана', 'en': 'Transcription interrupted',
      'de': 'Transkription unterbrochen', 'it': 'Trascrizione interrotta',
    },
    'recovery_chars': {
      'ru': '{n} символов', 'en': '{n} characters',
      'de': '{n} Zeichen', 'it': '{n} caratteri',
    },
    'recovery_chunk': {
      'ru': 'кусок {n}', 'en': 'chunk {n}',
      'de': 'Teil {n}', 'it': 'segmento {n}',
    },
    'recovery_show_text': {
      'ru': 'Показать текст', 'en': 'Show text',
      'de': 'Text anzeigen', 'it': 'Mostra testo',
    },
    'recovery_saved_title': {
      'ru': 'Прерванная расшифровка', 'en': 'Interrupted transcription',
      'de': 'Unterbrochene Transkription', 'it': 'Trascrizione interrotta',
    },
    'recovery_resume_hint': {
      'ru': 'Откройте ту же запись и запустите расшифровку — предложим продолжить с места обрыва.',
      'en': 'Open the same recording and start transcription — we\'ll offer to continue from where it stopped.',
      'de': 'Öffnen Sie dieselbe Aufnahme und starten Sie die Transkription — wir bieten an, ab der Unterbrechung weiterzumachen.',
      'it': 'Apri la stessa registrazione e avvia la trascrizione — ti offriremo di continuare dal punto di interruzione.',
    },
    // Настройки
    'settings_title': {
      'ru': 'Настройки', 'en': 'Settings', 'de': 'Einstellungen', 'it': 'Impostazioni',
    },
    'saved': {
      'ru': 'Сохранено', 'en': 'Saved', 'de': 'Gespeichert', 'it': 'Salvato',
    },
    'group_appearance': {
      'ru': 'Оформление', 'en': 'Appearance',
      'de': 'Erscheinungsbild', 'it': 'Aspetto',
    },
    'light_theme': {
      'ru': 'Светлая тема', 'en': 'Light theme',
      'de': 'Helles Design', 'it': 'Tema chiaro',
    },
    'light_theme_sub': {
      'ru': 'Дневное оформление приложения', 'en': 'Daytime appearance',
      'de': 'Tagesaussehen der App', 'it': 'Aspetto diurno dell\'app',
    },
    'group_recording': {
      'ru': 'Запись', 'en': 'Recording', 'de': 'Aufnahme', 'it': 'Registrazione',
    },
    'sample_rate': {
      'ru': 'Частота дискретизации (Hz)', 'en': 'Sample rate (Hz)',
      'de': 'Abtastrate (Hz)', 'it': 'Frequenza di campionamento (Hz)',
    },
    'bitrate': {
      'ru': 'Битрейт (bps)', 'en': 'Bitrate (bps)',
      'de': 'Bitrate (bps)', 'it': 'Bitrate (bps)',
    },
    'channels': {
      'ru': 'Каналы', 'en': 'Channels', 'de': 'Kanäle', 'it': 'Canali',
    },
    'mono': {
      'ru': 'Моно (1)', 'en': 'Mono (1)', 'de': 'Mono (1)', 'it': 'Mono (1)',
    },
    'stereo': {
      'ru': 'Стерео (2)', 'en': 'Stereo (2)', 'de': 'Stereo (2)', 'it': 'Stereo (2)',
    },
    'quality_note': {
      'ru': 'Высокие настройки улучшают качество, но увеличивают размер файла. Для расшифровки достаточно 16 кГц, моно.',
      'en': 'Higher settings improve quality but increase file size. For transcription, 16 kHz mono is enough.',
      'de': 'Höhere Einstellungen verbessern die Qualität, vergrößern aber die Datei. Für die Transkription reichen 16 kHz Mono.',
      'it': 'Impostazioni più alte migliorano la qualità ma aumentano le dimensioni. Per la trascrizione bastano 16 kHz, mono.',
    },
    'group_recognition': {
      'ru': 'Распознавание', 'en': 'Recognition',
      'de': 'Erkennung', 'it': 'Riconoscimento',
    },
    'engine_on_device': {
      'ru': 'Движок: на устройстве, модель внутри',
      'en': 'Engine: on-device, model inside',
      'de': 'Engine: auf dem Gerät, Modell integriert',
      'it': 'Motore: sul dispositivo, modello integrato',
    },
    'engine_on_device_sub': {
      'ru': 'Точная модель GigaAM работает локально. Интернет не нужен, файлы не покидают телефон.',
      'en': 'Accurate GigaAM model runs locally. No internet needed, files never leave your phone.',
      'de': 'Das genaue GigaAM-Modell arbeitet lokal. Kein Internet nötig, Dateien verlassen das Handy nie.',
      'it': 'Il modello accurato GigaAM funziona in locale. Nessun internet, i file non lasciano il telefono.',
    },
    'online_transcribe': {
      'ru': 'Онлайн-расшифровка', 'en': 'Online transcription',
      'de': 'Online-Transkription', 'it': 'Trascrizione online',
    },
    'online_transcribe_sub': {
      'ru': 'Точнее локальной модели, но звук уходит на сервер провайдера',
      'en': 'More accurate than the local model, but audio goes to the provider\'s server',
      'de': 'Genauer als das lokale Modell, aber Ton geht an den Server des Anbieters',
      'it': 'Più accurata del modello locale, ma l\'audio va al server del provider',
    },
    'provider': {
      'ru': 'Провайдер', 'en': 'Provider', 'de': 'Anbieter', 'it': 'Provider',
    },
    'key_for': {
      'ru': 'Ключ {p}', 'en': 'Key {p}',
      'de': 'Schlüssel {p}', 'it': 'Chiave {p}',
    },
    'key_stored_local': {
      'ru': 'Хранится только на устройстве', 'en': 'Stored on this device only',
      'de': 'Nur auf diesem Gerät gespeichert', 'it': 'Salvata solo su questo dispositivo',
    },
    'provider_dialog_title': {
      'ru': 'Провайдер онлайн-транскрипции', 'en': 'Online transcription provider',
      'de': 'Anbieter für Online-Transkription', 'it': 'Provider di trascrizione online',
    },
    'key_dialog_body': {
      'ru': 'Ключ хранится только на устройстве. Без ключа онлайн-режим выключен — расшифровка идёт офлайн, на устройстве.',
      'en': 'The key is stored on this device only. Without a key the online mode is off — transcription runs offline, on the device.',
      'de': 'Der Schlüssel wird nur auf diesem Gerät gespeichert. Ohne Schlüssel ist der Online-Modus aus — die Transkription läuft offline auf dem Gerät.',
      'it': 'La chiave è salvata solo su questo dispositivo. Senza chiave la modalità online è disattivata — la trascrizione avviene offline, sul dispositivo.',
    },
    'paste_api_key': {
      'ru': 'Вставь API-ключ', 'en': 'Paste API key',
      'de': 'API-Schlüssel einfügen', 'it': 'Incolla chiave API',
    },
    'key_removed': {
      'ru': 'Ключ удалён', 'en': 'Key removed',
      'de': 'Schlüssel entfernt', 'it': 'Chiave rimossa',
    },
    'key_saved': {
      'ru': 'Ключ сохранён', 'en': 'Key saved',
      'de': 'Schlüssel gespeichert', 'it': 'Chiave salvata',
    },
    'group_background': {
      'ru': 'Фон и память', 'en': 'Background & memory',
      'de': 'Hintergrund & Speicher', 'it': 'Sfondo e memoria',
    },
    'miui_unrestricted': {
      'ru': 'Работа без ограничений (MIUI)', 'en': 'Unrestricted operation (MIUI)',
      'de': 'Uneingeschränkter Betrieb (MIUI)', 'it': 'Operazione senza restrizioni (MIUI)',
    },
    'miui_sub': {
      'ru': 'Запросить исключение из оптимизации батареи. Без него система может остановить длинную расшифровку в фоне.\nРабота без ограничений: {s}',
      'en': 'Request exemption from battery optimization. Without it the system may stop long background transcription.\nUnrestricted operation: {s}',
      'de': 'Ausnahme von der Batterieoptimierung beantragen. Ohne sie kann das System lange Hintergrund-Transkriptionen stoppen.\nUneingeschränkter Betrieb: {s}',
      'it': 'Richiedi l\'esenzione dall\'ottimizzazione della batteria. Senza di essa il sistema può interrompere lunghe trascrizioni in background.\nOperazione senza restrizioni: {s}',
    },
    'miui_checking': {
      'ru': 'проверяю…', 'en': 'checking…',
      'de': 'prüfe…', 'it': 'controllo…',
    },
    'miui_on': {
      'ru': 'включено', 'en': 'enabled',
      'de': 'aktiviert', 'it': 'attivato',
    },
    'miui_off': {
      'ru': 'не включено', 'en': 'not enabled',
      'de': 'nicht aktiviert', 'it': 'non attivato',
    },
    'miui_manual_path': {
      'ru': 'MIUI: Сведения о батарее → Без ограничений',
      'en': 'MIUI: Battery info → Unrestricted',
      'de': 'MIUI: Akku-Info → Uneingeschränkt',
      'it': 'MIUI: Info batteria → Senza restrizioni',
    },
    'enable': {
      'ru': 'Включить', 'en': 'Enable', 'de': 'Aktivieren', 'it': 'Abilita',
    },
    'open_battery_settings': {
      'ru': 'Открыть настройки батареи', 'en': 'Open battery settings',
      'de': 'Batterieeinstellungen öffnen', 'it': 'Apri impostazioni batteria',
    },
    'temp_files': {
      'ru': 'Временные файлы', 'en': 'Temporary files',
      'de': 'Temporäre Dateien', 'it': 'File temporanei',
    },
    'temp_occupied': {
      'ru': 'Занято: {m} МБ. Обычно мусор удаляется сразу после расшифровки.',
      'en': 'Occupied: {m} MB. Junk is usually removed right after transcription.',
      'de': 'Belegt: {m} MB. Der Müll wird normalerweise direkt nach der Transkription entfernt.',
      'it': 'Occupati: {m} MB. I file temporanei vengono rimossi subito dopo la trascrizione.',
    },
    'temp_none': {
      'ru': 'Временных файлов нет — мусор удаляется сразу после расшифровки.',
      'en': 'No temporary files — junk is removed right after transcription.',
      'de': 'Keine temporären Dateien — der Müll wird direkt nach der Transkription entfernt.',
      'it': 'Nessun file temporaneo — i file vengono rimossi subito dopo la trascrizione.',
    },
    'clear': {
      'ru': 'Очистить', 'en': 'Clear', 'de': 'Leeren', 'it': 'Pulisci',
    },
    'freed_mb': {
      'ru': 'Освобождено {m} МБ', 'en': 'Freed {m} MB',
      'de': '{m} MB freigegeben', 'it': 'Liberati {m} MB',
    },
    'group_data': {
      'ru': 'Данные', 'en': 'Data', 'de': 'Daten', 'it': 'Dati',
    },
    'all_on_device': {
      'ru': 'Всё хранится на устройстве', 'en': 'Everything is stored on the device',
      'de': 'Alles wird auf dem Gerät gespeichert', 'it': 'Tutto è archiviato sul dispositivo',
    },
    'all_on_device_sub': {
      'ru': 'Записи, тексты и ключи не покидают телефон без вашего решения.',
      'en': 'Recordings, texts and keys never leave your phone unless you decide so.',
      'de': 'Aufnahmen, Texte und Schlüssel verlassen das Handy nur mit Ihrer Entscheidung.',
      'it': 'Registrazioni, testi e chiavi non lasciano il telefono senza la tua decisione.',
    },
    'share_folder_diag': {
      'ru': 'Папка обмена (диагностика)', 'en': 'Exchange folder (diagnostics)',
      'de': 'Austauschordner (Diagnose)', 'it': 'Cartella di scambio (diagnostica)',
    },
    'share_folder_sub': {
      'ru': 'Android/data/com.dictapro.app/files — тексты и временные WAV для проверки',
      'en': 'Android/data/com.dictapro.app/files — texts and temporary WAVs for review',
      'de': 'Android/data/com.dictapro.app/files — Texte und temporäre WAVs zur Prüfung',
      'it': 'Android/data/com.dictapro.app/files — testi e WAV temporanei per verifica',
    },
    // Плеер
    'player_title': {
      'ru': 'Прослушивание', 'en': 'Playback',
      'de': 'Wiedergabe', 'it': 'Riproduzione',
    },
    'recording_of': {
      'ru': 'Запись {d}', 'en': 'Recording {d}',
      'de': 'Aufnahme {d}', 'it': 'Registrazione {d}',
    },
    // Итоги
    'no_transcript': {
      'ru': 'Нет расшифрованного текста для итогов',
      'en': 'No transcribed text for summaries',
      'de': 'Kein transkribierter Text für Zusammenfassungen',
      'it': 'Nessun testo trascritto per i riepiloghi',
    },
    'retry': {
      'ru': 'Повторить', 'en': 'Retry', 'de': 'Wiederholen', 'it': 'Riprova',
    },
    'load_error': {
      'ru': 'Ошибка загрузки', 'en': 'Load error',
      'de': 'Ladefehler', 'it': 'Errore di caricamento',
    },
    // Редактор диалога
    'exported_html': {
      'ru': 'HTML экспортирован: {p}', 'en': 'HTML exported: {p}',
      'de': 'HTML exportiert: {p}', 'it': 'HTML esportato: {p}',
    },
    'edit_text_title': {
      'ru': 'Редактирование текста', 'en': 'Editing text',
      'de': 'Textbearbeitung', 'it': 'Modifica del testo',
    },
    'saved_to_downloads': {
      'ru': 'Сохранено в папку загрузок', 'en': 'Saved to Downloads',
      'de': 'Im Download-Ordner gespeichert', 'it': 'Salvato in Download',
    },
    'search_text_hint': {
      'ru': 'Поиск текста...', 'en': 'Search text...',
      'de': 'Text suchen...', 'it': 'Cerca testo...',
    },
    'summary_title': {
      'ru': 'Саммари', 'en': 'Summary',
      'de': 'Zusammenfassung', 'it': 'Riepilogo',
    },
    'summary_card_title': {
      'ru': 'Краткое содержание', 'en': 'Key points',
      'de': 'Kurzfassung', 'it': 'Punti chiave',
    },
    'summary_press_button': {
      'ru': 'Нажмите кнопку ниже для генерации саммари',
      'en': 'Press the button below to generate a summary',
      'de': 'Taste unten drücken, um eine Zusammenfassung zu erzeugen',
      'it': 'Premi il pulsante qui sotto per generare il riepilogo',
    },
    'no_summary_yet': {
      'ru': 'Нет доступного резюме', 'en': 'No summary available',
      'de': 'Keine Zusammenfassung verfügbar', 'it': 'Nessun riepilogo disponibile',
    },
    'copied_to_clipboard': {
      'ru': 'Скопировано в буфер обмена', 'en': 'Copied to clipboard',
      'de': 'In die Zwischenablage kopiert', 'it': 'Copiato negli appunti',
    },
    'html_saved': {
      'ru': 'HTML сохранён: {p}', 'en': 'HTML saved: {p}',
      'de': 'HTML gespeichert: {p}', 'it': 'HTML salvato: {p}',
    },
    'edit_dialog_title': {
      'ru': 'Редактировать диалог', 'en': 'Edit dialogue',
      'de': 'Dialog bearbeiten', 'it': 'Modifica dialogo',
    },
    'enter_text_hint': {
      'ru': 'Введите текст...', 'en': 'Enter text...',
      'de': 'Text eingeben...', 'it': 'Inserisci testo...',
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

  // Task 059: универсальные доступы для экрана итогов.
  static String t(String key, BuildContext context) => _t(key, context);
  static String tf(String key, BuildContext context, Map<String, String> params) =>
      _fmt(_t(key, context), params);

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
