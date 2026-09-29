// Локализованные строки DictaPro (tasks 052, 053).
// Полноценной i18n-инфраструктуры в проекте нет — UI исторически русский.
// Здесь компактный словарь для строк, которые ТЗ требует на 4 языках
// (ru/en/de/it). Язык берём из системной локали, дефолт — русский.
// Смысловой слоган линейки: запись и распознавание идут на устройстве,
// данные никуда не отправляются.
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'locale_controller.dart';

class AppStrings {
  AppStrings._();

  /// Словарь: ключ → {код языка: строка}. Русский — обязательный fallback.
  static const _dict = <String, Map<String, String>>{
    'splash_slogan': {
      'ru': 'Не покидая телефон', 'es': 'Nunca sale de tu teléfono', 'fr': 'Ne quitte jamais votre téléphone',
      'en': 'Never leaves your phone',
      'de': 'Verlässt dein Handy nie',
      'it': 'Non lascia mai il telefono',
    },
    // Task 053: предупреждение перед расшифровкой длинной записи (>5 ч).
    // {d} — длительность записи («16 ч 40 мин»), {e} — оценка времени («≈ 3 ч»).
    'long_transcribe_title': {
      'ru': 'Длинная запись', 'es': 'Grabación larga', 'fr': 'Enregistrement long',
      'en': 'Long recording',
      'de': 'Lange Aufnahme',
      'it': 'Registrazione lunga',
    },
    'long_transcribe_body': {
      'ru': 'Запись {d}. Расшифровка может занять несколько часов (≈ {e}). Продолжить?', 'es': 'Grabación {d}. La transcripción puede tardar varias horas (≈ {e}). ¿Continuar?', 'fr': 'Enregistrement {d}. La transcription peut prendre plusieurs heures (≈ {e}). Continuer ?',
      'en': 'Recording {d}. Transcription may take several hours (≈ {e}). Continue?',
      'de': 'Aufnahme {d}. Die Transkription kann mehrere Stunden dauern (≈ {e}). Fortfahren?',
      'it': 'Registrazione {d}. La trascrizione può richiedere diverse ore (≈ {e}). Continuare?',
    },
    'long_transcribe_continue': {
      'ru': 'Продолжить', 'es': 'Continuar', 'fr': 'Continuer',
      'en': 'Continue',
      'de': 'Fortfahren',
      'it': 'Continuare',
    },
    'long_transcribe_cancel': {
      'ru': 'Отмена', 'es': 'Cancelar', 'fr': 'Annuler',
      'en': 'Cancel',
      'de': 'Abbrechen',
      'it': 'Annulla',
    },
    // Task 054: монетизация — лимит исчерпан → paywall.
    // {n} — дневной лимит минут, {u} — уже использовано сегодня.
    // Task 059: два вида итогов + ИИ-часы.
    'summary_local_btn': {
      'ru': 'Итоги локально', 'es': 'Resumen local', 'fr': 'Résumé local',
      'en': 'On-device summary',
      'de': 'Zusammenfassung lokal',
      'it': 'Riepilogo locale',
    },
    'summary_online_btn': {
      'ru': 'Итоги онлайн', 'es': 'Resumen online', 'fr': 'Résumé en ligne',
      'en': 'Online summary',
      'de': 'Zusammenfassung online',
      'it': 'Riepilogo online',
    },
    'online_summary_warning_title': {
      'ru': 'Отправить на сервер?', 'es': '¿Enviar al servidor?', 'fr': 'Envoyer au serveur ?',
      'en': 'Send to server?',
      'de': 'An den Server senden?',
      'it': 'Inviare al server?',
    },
    'online_summary_warning_body': {
      'ru': 'Функцию запускаете вы сами. Текст записи уйдёт на наш сервер для обработки и вернётся итогами. Локальные итоги работают без интернета и без отправки данных. Продолжить?', 'es': 'Inicias tú mismo esta función. El texto de la grabación se enviará a nuestro servidor para su procesamiento y volverá en forma de resumen. Los resúmenes locales funcionan sin internet y sin enviar datos. ¿Continuar?', 'fr': 'Vous lancez cette fonction vous-même. Le texte de l\'enregistrement sera envoyé à notre serveur pour traitement et renvoyé sous forme de résumés. Les résumés locaux fonctionnent hors ligne, sans envoi de données. Continuer ?',
      'en': 'You run this feature yourself. The recording text will be sent to our server for processing and come back as summaries. On-device summaries work offline without sending any data. Continue?',
      'de': 'Sie starten diese Funktion selbst. Der Aufnahmetext wird zur Verarbeitung an unseren Server gesendet und als Zusammenfassung zurückgesendet. Lokale Zusammenfassungen funktionieren offline ohne Datenversand. Fortfahren?',
      'it': 'Avvii tu questa funzione. Il testo della registrazione verrà inviato al nostro server per l\'elaborazione e restituito come riepilogo. I riepiloghi locali funzionano offline senza invio di dati. Continuare?',
    },
    'online_summary_cancel': {
      'ru': 'Отмена', 'es': 'Cancelar', 'fr': 'Annuler', 'en': 'Cancel', 'de': 'Abbrechen', 'it': 'Annulla',
    },
    'online_summary_send': {
      'ru': 'Отправить', 'es': 'Enviar', 'fr': 'Envoyer', 'en': 'Send', 'de': 'Senden', 'it': 'Invia',
    },
    'online_summary_stage': {
      'ru': 'Итоги на сервере…', 'es': 'Resumen en el servidor…', 'fr': 'Résumé sur le serveur…',
      'en': 'Summarizing on server…',
      'de': 'Zusammenfassung auf dem Server…',
      'it': 'Riepilogo sul server…',
    },
    'online_summary_title': {
      'ru': 'Итоги (онлайн)', 'es': 'Resumen (online)', 'fr': 'Résumé (en ligne)',
      'en': 'Summary (online)',
      'de': 'Zusammenfassung (online)',
      'it': 'Riepilogo (online)',
    },
    'online_summary_failed': {
      'ru': 'Не удалось получить итоги. Проверьте интернет и попробуйте позже.', 'es': 'No se pudo obtener el resumen. Comprueba la conexión a internet e inténtalo más tarde.', 'fr': 'Impossible d\'obtenir le résumé. Vérifiez votre connexion et réessayez plus tard.',
      'en': 'Could not get summaries. Check your internet and try again.',
      'de': 'Zusammenfassung fehlgeschlagen. Internet prüfen und erneut versuchen.',
      'it': 'Impossibile ottenere il riepilogo. Controlla internet e riprova.',
    },
    'online_summary_no_hours': {
      'ru': 'ИИ-часы закончились. Продлите подписку или докупите пакет часов.', 'es': 'Se han agotado las horas de IA. Renueva la suscripción o compra un paquete de horas.', 'fr': 'Les heures IA sont épuisées. Renouvelez votre abonnement ou achetez un pack d\'heures.',
      'en': 'AI hours are used up. Renew your subscription or buy an hours pack.',
      'de': 'KI-Stunden sind aufgebraucht. Abo verlängern oder Stundenpaket kaufen.',
      'it': 'Ore AI esaurite. Rinnova l\'abbonamento o acquista un pacchetto di ore.',
    },
    'online_summary_from_cache': {
      'ru': 'Взято из кэша — бесплатно.', 'es': 'Desde la caché — gratis.', 'fr': 'Servi depuis le cache — gratuit.',
      'en': 'Served from cache — free.',
      'de': 'Aus dem Cache — kostenlos.',
      'it': 'Dal cache — gratis.',
    },
    'online_summary_spent': {
      'ru': 'Списано {h} ИИ-ч.', 'es': 'Descontadas {h} h de IA.', 'fr': '{h} h IA débitées.',
      'en': 'Charged {h} AI hours.',
      'de': '{h} KI-Stunden abgebucht.',
      'it': 'Addebitate {h} ore AI.',
    },
    'online_summary_refresh': {
      'ru': 'Обновить', 'es': 'Actualizar', 'fr': 'Actualiser', 'en': 'Refresh', 'de': 'Aktualisieren', 'it': 'Aggiorna',
    },
    'limit_reached_title': {
      'ru': 'Лимит исчерпан', 'es': 'Límite alcanzado', 'fr': 'Limite atteinte',
      'en': 'Daily limit reached',
      'de': 'Tageslimit erreicht',
      'it': 'Limite giornaliero raggiunto',
    },
    'limit_reached_body': {
      'ru': 'Сегодня использовано {u} из {n} минут расшифровки.\n\n', 'es': 'Hoy has usado {u} de {n} minutos de transcripción.\n\nVersión completa — todo sin límites: transcripción en el dispositivo, resúmenes, etiquetas, exportación, búsqueda. Compra única.', 'fr': 'Aujourd\'hui, {u} minutes de transcription utilisées sur {n}.\n\nVersion complète — tout sans limites : transcription sur l\'appareil, résumés, tags, export, recherche. Achat unique.'
          'Полная версия — всё без лимитов: расшифровка на устройстве, итоги, теги, экспорт, поиск. Разовая покупка.',
      'en': 'You have used {u} of {n} transcription minutes today.\n\n'
          'Full version — everything without limits: on-device transcription, summaries, tags, export, search. One-time purchase.',
      'de': 'Heute wurden {u} von {n} Transkriptionsminuten verbraucht.\n\n'
          'Vollversion — alles ohne Limit: Transkription auf dem Gerät, Zusammenfassungen, Tags, Export, Suche. Einmaliger Kauf.',
      'it': 'Oggi hai usato {u} dei {n} minuti di trascrizione.\n\n'
          'Versione completa — tutto senza limiti: trascrizione sul dispositivo, riepiloghi, tag, esportazione, ricerca. Acquisto una tantum.',
    },
    'buy_full': {
      'ru': 'Купить полную версию', 'es': 'Comprar versión completa', 'fr': 'Acheter la version complète',
      'en': 'Buy full version',
      'de': 'Vollversion kaufen',
      'it': 'Acquista versione completa',
    },
    'restore_purchase': {
      'ru': 'Восстановить покупку', 'es': 'Restaurar compra', 'fr': 'Restaurer l\'achat',
      'en': 'Restore purchase',
      'de': 'Kauf wiederherstellen',
      'it': 'Ripristina acquisto',
    },
    'store_unavailable': {
      'ru': 'Магазин сейчас недоступен. Проверьте интернет и попробуйте позже.', 'es': 'La tienda no está disponible ahora mismo. Comprueba la conexión e inténtalo más tarde.', 'fr': 'La boutique est indisponible pour le moment. Vérifiez votre connexion et réessayez plus tard.',
      'en': 'The store is currently unavailable. Check your internet and try again later.',
      'de': 'Der Store ist derzeit nicht verfügbar. Prüfen Sie Ihre Internetverbindung.',
      'it': 'Lo store non è al momento disponibile. Controlla la connessione e riprova.',
    },

    // ---------- Task 060: полная локализация UI ----------
    'app_title': {
      'ru': 'ДиктаПро', 'es': 'DictaPro', 'fr': 'DictaPro', 'en': 'DictaPro', 'de': 'DictaPro', 'it': 'DictaPro',
    },
    // Главный экран
    'recording_now': {
      'ru': '● Идет запись...', 'es': '● Grabando...', 'fr': '● Enregistrement en cours...',
      'en': '● Recording...',
      'de': '● Aufnahme läuft...',
      'it': '● Registrazione in corso...',
    },
    'tap_to_record': {
      'ru': 'Нажмите для записи', 'es': 'Toca para grabar', 'fr': 'Appuyez pour enregistrer',
      'en': 'Tap to record',
      'de': 'Tippen zum Aufnehmen',
      'it': 'Tocca per registrare',
    },
    'start_recording': {
      'ru': 'Начать запись', 'es': 'Iniciar grabación', 'fr': 'Démarrer l\'enregistrement',
      'en': 'Start recording',
      'de': 'Aufnahme starten',
      'it': 'Inizia registrazione',
    },
    'stop_recording': {
      'ru': 'Остановить запись', 'es': 'Detener grabación', 'fr': 'Arrêter l\'enregistrement',
      'en': 'Stop recording',
      'de': 'Aufnahme stoppen',
      'it': 'Ferma registrazione',
    },
    'sleep_timer': {
      'ru': 'Таймер сна', 'es': 'Temporizador de apagado', 'fr': 'Minuteur de veille',
      'en': 'Sleep timer',
      'de': 'Schlaf-Timer',
      'it': 'Timer spegnimento',
    },
    'timer_active': {
      'ru': 'Таймер: {m} мин', 'es': 'Temporizador: {m} min', 'fr': 'Minuteur : {m} min',
      'en': 'Timer: {m} min',
      'de': 'Timer: {m} Min',
      'it': 'Timer: {m} min',
    },
    'timer_min': {
      'ru': '{m} мин', 'es': '{m} min', 'fr': '{m} min',
      'en': '{m} min',
      'de': '{m} Min',
      'it': '{m} min',
    },
    'timer_dialog_title': {
      'ru': 'Таймер остановки', 'es': 'Temporizador de parada', 'fr': 'Minuteur d\'arrêt',
      'en': 'Stop timer',
      'de': 'Stopp-Timer',
      'it': 'Timer di arresto',
    },
    'timer_none': {
      'ru': 'Без таймера', 'es': 'Sin temporizador', 'fr': 'Sans minuteur',
      'en': 'No timer',
      'de': 'Ohne Timer',
      'it': 'Nessun timer',
    },
    'minutes_15': {
      'ru': '15 минут', 'es': '15 minutos', 'fr': '15 minutes', 'en': '15 minutes', 'de': '15 Minuten', 'it': '15 minuti',
    },
    'minutes_30': {
      'ru': '30 минут', 'es': '30 minutos', 'fr': '30 minutes', 'en': '30 minutes', 'de': '30 Minuten', 'it': '30 minuti',
    },
    'minutes_60': {
      'ru': '60 минут', 'es': '60 minutos', 'fr': '60 minutes', 'en': '60 minutes', 'de': '60 Minuten', 'it': '60 minuti',
    },
    'hotwords_hint': {
      'ru': 'Термины этой записи (имена, аббревиатуры — через запятую)', 'es': 'Términos de esta grabación (nombres, abreviaturas — separados por comas)', 'fr': 'Termes de cet enregistrement (noms, abréviations — séparés par des virgules)',
      'en': 'Terms for this recording (names, abbreviations — comma separated)',
      'de': 'Begriffe dieser Aufnahme (Namen, Abkürzungen — kommagetrennt)',
      'it': 'Termini di questa registrazione (nomi, abbreviazioni — separati da virgola)',
    },
    'engine_label': {
      'ru': 'Распознавание: на устройстве · модель внутри', 'es': 'Reconocimiento: en el dispositivo · modelo integrado', 'fr': 'Reconnaissance : sur l\'appareil · modèle intégré',
      'en': 'Recognition: on-device · model inside',
      'de': 'Erkennung: auf dem Gerät · Modell integriert',
      'it': 'Riconoscimento: sul dispositivo · modello integrato',
    },
    'settings_tooltip': {
      'ru': 'Настройки', 'es': 'Ajustes', 'fr': 'Paramètres', 'en': 'Settings', 'de': 'Einstellungen', 'it': 'Impostazioni',
    },
    'search_hint': {
      'ru': 'Поиск по транскрипциям...', 'es': 'Buscar en las transcripciones...', 'fr': 'Rechercher dans les transcriptions...',
      'en': 'Search transcripts...',
      'de': 'Transkripte durchsuchen...',
      'it': 'Cerca nelle trascrizioni...',
    },
    'favorites_count': {
      'ru': 'Избранное ({n})', 'es': 'Favoritos ({n})', 'fr': 'Favoris ({n})', 'en': 'Favorites ({n})',
      'de': 'Favoriten ({n})', 'it': 'Preferiti ({n})',
    },
    'recordings_count': {
      'ru': 'Записи ({n})', 'es': 'Grabaciones ({n})', 'fr': 'Enregistrements ({n})', 'en': 'Recordings ({n})',
      'de': 'Aufnahmen ({n})', 'it': 'Registrazioni ({n})',
    },
    'found_count': {
      'ru': 'Найдено: {n}', 'es': 'Encontrados: {n}', 'fr': 'Trouvés : {n}', 'en': 'Found: {n}',
      'de': 'Gefunden: {n}', 'it': 'Trovati: {n}',
    },
    'sort_tooltip': {
      'ru': 'Сортировка', 'es': 'Ordenar', 'fr': 'Tri', 'en': 'Sort', 'de': 'Sortierung', 'it': 'Ordinamento',
    },
    'sort_date_newest': {
      'ru': 'Дата (новые)', 'es': 'Fecha (más recientes)', 'fr': 'Date (récentes)', 'en': 'Date (newest)',
      'de': 'Datum (neueste)', 'it': 'Data (recenti)',
    },
    'sort_date_oldest': {
      'ru': 'Дата (старые)', 'es': 'Fecha (más antiguas)', 'fr': 'Date (anciennes)', 'en': 'Date (oldest)',
      'de': 'Datum (älteste)', 'it': 'Data (più vecchie)',
    },
    'sort_name_asc': {
      'ru': 'Имя (А-Я)', 'es': 'Nombre (A-Z)', 'fr': 'Nom (A-Z)', 'en': 'Name (A-Z)',
      'de': 'Name (A-Z)', 'it': 'Nome (A-Z)',
    },
    'sort_duration_longest': {
      'ru': 'Длительность (длинные)', 'es': 'Duración (más largas)', 'fr': 'Durée (longues)', 'en': 'Duration (longest)',
      'de': 'Dauer (längste)', 'it': 'Durata (più lunghe)',
    },
    'sort_duration_shortest': {
      'ru': 'Длительность (короткие)', 'es': 'Duración (más cortas)', 'fr': 'Durée (courtes)', 'en': 'Duration (shortest)',
      'de': 'Dauer (kürzeste)', 'it': 'Durata (più corte)',
    },
    'empty_search_title': {
      'ru': 'Ничего не нашлось', 'es': 'No se encontró nada', 'fr': 'Aucun résultat', 'en': 'Nothing found',
      'de': 'Nichts gefunden', 'it': 'Nessun risultato',
    },
    'empty_search_body': {
      'ru': 'Попробуйте другое слово или очистите поиск.', 'es': 'Prueba con otra palabra o borra la búsqueda.', 'fr': 'Essayez un autre mot ou effacez la recherche.',
      'en': 'Try another word or clear the search.',
      'de': 'Anderes Wort versuchen oder Suche leeren.',
      'it': 'Prova un\'altra parola o cancella la ricerca.',
    },
    'empty_rec_title': {
      'ru': 'Пока ни одной записи', 'es': 'Aún no hay grabaciones', 'fr': 'Aucun enregistrement pour l\'instant', 'en': 'No recordings yet',
      'de': 'Noch keine Aufnahmen', 'it': 'Nessuna registrazione',
    },
    'empty_rec_body': {
      'ru': 'Нажмите большую кнопку «Начать запись» — или импортируйте готовый файл (mp3, m4a, wav) и расшифруйте его.', 'es': 'Pulsa el botón grande «Iniciar grabación» — o importa un archivo existente (mp3, m4a, wav) y transcríbelo.', 'fr': 'Appuyez sur le grand bouton « Démarrer l\'enregistrement » — ou importez un fichier existant (mp3, m4a, wav) et transcrivez-le.',
      'en': 'Tap the big "Start recording" button — or import an existing file (mp3, m4a, wav) and transcribe it.',
      'de': 'Tippen Sie auf die große Taste „Aufnahme starten“ — oder importieren Sie eine Datei (mp3, m4a, wav) und transkribieren Sie sie.',
      'it': 'Tocca il grande pulsante «Inizia registrazione» — oppure importa un file (mp3, m4a, wav) e trascrivilo.',
    },
    'btn_dialog': {
      'ru': 'Диалог', 'es': 'Diálogo', 'fr': 'Dialogue', 'en': 'Dialogue', 'de': 'Dialog', 'it': 'Dialogo',
    },
    'btn_to_text': {
      'ru': 'В текст', 'es': 'A texto', 'fr': 'En texte', 'en': 'To text', 'de': 'Zu Text', 'it': 'A testo',
    },
    'btn_gist': {
      'ru': 'Суть', 'es': 'Idea clave', 'fr': 'Essentiel', 'en': 'Gist', 'de': 'Kernaussage', 'it': 'Sintesi',
    },
    'btn_redo': {
      'ru': 'Заново', 'es': 'Regenerar', 'fr': 'Refaire', 'en': 'Redo',
      'de': 'Neu', 'it': 'Rifai',
    },
    'btn_send': {
      'ru': 'Отправить', 'es': 'Enviar', 'fr': 'Envoyer', 'en': 'Send', 'de': 'Senden', 'it': 'Invia',
    },
    'btn_listen': {
      'ru': 'Слушать', 'es': 'Escuchar', 'fr': 'Écouter', 'en': 'Listen', 'de': 'Anhören', 'it': 'Ascolta',
    },
    'btn_delete': {
      'ru': 'Удалить', 'es': 'Eliminar', 'fr': 'Supprimer', 'en': 'Delete', 'de': 'Löschen', 'it': 'Elimina',
    },
    // Расшифровка / прогресс
    'transcribing_now': {
      'ru': 'Идёт расшифровка', 'es': 'Transcripción en curso', 'fr': 'Transcription en cours', 'en': 'Transcribing',
      'de': 'Transkription läuft', 'it': 'Trascrizione in corso',
    },
    'live_running_min': {
      'ru': 'идёт {m} мин', 'es': 'lleva {m} min', 'fr': 'en cours depuis {m} min', 'en': 'running {m} min',
      'de': 'läuft seit {m} Min', 'it': 'in corso da {m} min',
    },
    'live_chunks_done': {
      'ru': 'готово кусков: {n}', 'es': 'fragmentos listos: {n}', 'fr': 'segments terminés : {n}', 'en': 'chunks done: {n}',
      'de': 'fertige Teile: {n}', 'it': 'segmenti pronti: {n}',
    },
    'live_chars': {
      'ru': 'символов: {n}', 'es': 'caracteres: {n}', 'fr': 'caractères : {n}', 'en': 'characters: {n}',
      'de': 'Zeichen: {n}', 'it': 'caratteri: {n}',
    },
    'transcribe_already': {
      'ru': 'Расшифровка уже идёт — дождитесь окончания', 'es': 'La transcripción ya está en curso — espera a que termine', 'fr': 'La transcription est déjà en cours — veuillez patienter',
      'en': 'Transcription is already running — please wait',
      'de': 'Transkription läuft bereits — bitte warten',
      'it': 'La trascrizione è già in corso — attendi',
    },
    'op_transcribing': {
      'ru': 'Расшифровка…', 'es': 'Transcribiendo…', 'fr': 'Transcription…', 'en': 'Transcribing…',
      'de': 'Transkribieren…', 'it': 'Trascrizione…',
    },
    'creating_pdf': {
      'ru': 'Создание PDF...', 'es': 'Creando PDF...', 'fr': 'Création du PDF...', 'en': 'Creating PDF...',
      'de': 'PDF wird erstellt...', 'it': 'Creazione PDF...',
    },
    'online_recognizing': {
      'ru': 'Онлайн-распознавание…', 'es': 'Reconocimiento online…', 'fr': 'Reconnaissance en ligne…', 'en': 'Online recognition…',
      'de': 'Online-Erkennung…', 'it': 'Riconoscimento online…',
    },
    'online_failed': {
      'ru': 'Онлайн не удался, остаёмся офлайн: {e}', 'es': 'El modo online falló, seguimos offline: {e}', 'fr': 'Échec du mode en ligne, on reste hors ligne : {e}',
      'en': 'Online failed, staying offline: {e}',
      'de': 'Online fehlgeschlagen, bleibe offline: {e}',
      'it': 'Online non riuscito, resto offline: {e}',
    },
    'offline_warn_title': {
      'ru': 'Вы выходите из офлайн-режима', 'es': 'Vas a salir del modo offline', 'fr': 'Vous quittez le mode hors ligne',
      'en': 'You are leaving offline mode',
      'de': 'Sie verlassen den Offline-Modus',
      'it': 'Stai uscendo dalla modalità offline',
    },
    'offline_warn_body': {
      'ru': 'Обычно все записи остаются только на этом устройстве. Для точного распознавания звук этой записи будет отправлен на сервер ({p}). Больше ничего не передаётся.', 'es': 'Normalmente todas las grabaciones se quedan solo en este dispositivo. Para un reconocimiento preciso, el audio de esta grabación se enviará al servidor ({p}). No se transmite nada más.', 'fr': 'D\'habitude, tous les enregistrements restent uniquement sur cet appareil. Pour une reconnaissance précise, l\'audio de cet enregistrement sera envoyé au serveur ({p}). Rien d\'autre n\'est transmis.',
      'en': 'Usually all recordings stay on this device only. For accurate recognition, this recording\'s audio will be sent to the server ({p}). Nothing else is transmitted.',
      'de': 'Normalerweise bleiben alle Aufnahmen nur auf diesem Gerät. Für eine genaue Erkennung wird der Ton dieser Aufnahme an den Server gesendet ({p}). Es wird nichts weiter übertragen.',
      'it': 'Di solito tutte le registrazioni restano solo su questo dispositivo. Per un riconoscimento accurato, l\'audio di questa registrazione verrà inviato al server ({p}). Non viene trasmesso altro.',
    },
    'stay_offline': {
      'ru': 'Остаться офлайн', 'es': 'Seguir offline', 'fr': 'Rester hors ligne', 'en': 'Stay offline',
      'de': 'Offline bleiben', 'it': 'Rimani offline',
    },
    'recognize_online': {
      'ru': 'Распознать онлайн', 'es': 'Reconocer online', 'fr': 'Reconnaître en ligne', 'en': 'Recognize online',
      'de': 'Online erkennen', 'it': 'Riconosci online',
    },
    'unfinished_title': {
      'ru': 'Незавершённая расшифровка', 'es': 'Transcripción sin terminar', 'fr': 'Transcription inachevée', 'en': 'Unfinished transcription',
      'de': 'Unvollständige Transkription', 'it': 'Trascrizione incompleta',
    },
    'unfinished_body': {
      'ru': 'В прошлый раз распознание оборвалось на куске {c} ({s} символов текста уже готово).\n\nПродолжить с этого места или начать заново?', 'es': 'La última vez el reconocimiento se detuvo en el fragmento {c} ({s} caracteres de texto ya listos).\n\n¿Continuar desde ahí o empezar de nuevo?', 'fr': 'La dernière fois, la reconnaissance s\'est arrêtée au segment {c} ({s} caractères de texte déjà transcrits).\n\nContinuer à partir de là ou recommencer ?',
      'en': 'Last time recognition stopped at chunk {c} ({s} characters of text already done).\n\nContinue from there or start over?',
      'de': 'Beim letzten Mal wurde die Erkennung bei Teil {c} unterbrochen ({s} Zeichen Text bereits fertig).\n\nVon dort fortfahren oder neu beginnen?',
      'it': 'L\'ultima volta il riconoscimento si è interrotto al segmento {c} ({s} caratteri di testo già pronti).\n\nContinuare da lì o ricominciare?',
    },
    'start_over': {
      'ru': 'Начать заново', 'es': 'Empezar de nuevo', 'fr': 'Recommencer', 'en': 'Start over',
      'de': 'Neu beginnen', 'it': 'Ricomincia',
    },
    'keepalive_prep': {
      'ru': 'Расшифровка: готовлю аудио…', 'es': 'Transcripción: preparando el audio…', 'fr': 'Transcription : préparation de l\'audio…', 'en': 'Transcription: preparing audio…',
      'de': 'Transkription: Audiovorbereitung…', 'it': 'Trascrizione: preparazione audio…',
    },
    'stage_prep_audio': {
      'ru': 'Готовим аудио (декодирование)…', 'es': 'Preparando el audio (decodificación)…', 'fr': 'Préparation de l\'audio (décodage)…', 'en': 'Preparing audio (decoding)…',
      'de': 'Audio vorbereiten (Decodierung)…', 'it': 'Preparazione audio (decodifica)…',
    },
    'stage_resume_skip': {
      'ru': 'Продолжаем: пропускаем {n} готовых кусков…', 'es': 'Reanudando: omitiendo {n} fragmentos ya listos…', 'fr': 'Reprise : {n} segments déjà terminés sont ignorés…',
      'en': 'Resuming: skipping {n} finished chunks…',
      'de': 'Fortsetzen: {n} fertige Teile werden übersprungen…',
      'it': 'Ripresa: salto {n} segmenti già pronti…',
    },
    'stage_transcribing': {
      'ru': 'Расшифровка идёт…', 'es': 'Transcribiendo…', 'fr': 'Transcription en cours…', 'en': 'Transcribing…',
      'de': 'Transkription läuft…', 'it': 'Trascrizione in corso…',
    },
    'chunk_progress': {
      'ru': 'Кусок {d} из {a}', 'es': 'Fragmento {d} de {a}', 'fr': 'Segment {d} sur {a}', 'en': 'Chunk {d} of {a}',
      'de': 'Teil {d} von {a}', 'it': 'Segmento {d} di {a}',
    },
    'elapsed': {
      'ru': 'прошло {t}', 'es': 'transcurrido {t}', 'fr': 'écoulé : {t}', 'en': 'elapsed {t}',
      'de': '{t} vergangen', 'it': 'trascorso {t}',
    },
    'on_device_note': {
      'ru': 'Считается на устройстве — можно не держать экран открытым', 'es': 'Se procesa en el dispositivo — no hace falta dejar la pantalla encendida', 'fr': 'Calcul effectué sur l\'appareil — vous pouvez éteindre l\'écran',
      'en': 'Runs on-device — you can turn the screen off',
      'de': 'Läuft auf dem Gerät — der Bildschirm kann aus bleiben',
      'it': 'Funziona sul dispositivo — puoi spegnere lo schermo',
    },
    'model_prep_title': {
      'ru': 'Подготовка модели', 'es': 'Preparación del modelo', 'fr': 'Préparation du modèle',
      'en': 'Preparing model',
      'de': 'Modell wird vorbereitet',
      'it': 'Preparazione del modello',
    },
    // Task 067: fast-follow — Play догружает пакет модели после установки.
    'model_prep_download': {
      'ru': 'Загружается модель распознавания…', 'es': 'Descargando el modelo de reconocimiento…', 'fr': 'Téléchargement du modèle de reconnaissance…',
      'en': 'Downloading speech model…',
      'de': 'Sprachmodell wird heruntergeladen…',
      'it': 'Download del modello vocale…',
    },
    'summary_computing': {
      'ru': 'Считаю саммари…', 'es': 'Generando el resumen…', 'fr': 'Calcul du résumé…', 'en': 'Computing summary…',
      'de': 'Zusammenfassung wird erstellt…', 'it': 'Calcolo del riepilogo…',
    },
    'summary_part': {
      'ru': 'Считаю саммари… часть {d} из {t}', 'es': 'Generando el resumen… parte {d} de {t}', 'fr': 'Calcul du résumé… partie {d} sur {t}',
      'en': 'Computing summary… part {d} of {t}',
      'de': 'Zusammenfassung… Teil {d} von {t}',
      'it': 'Calcolo riepilogo… parte {d} di {t}',
    },
    'summary_failed': {
      'ru': 'Итоги: не удалось собрать', 'es': 'Resumen: no se pudo generar', 'fr': 'Résumé : échec de la génération', 'en': 'Summary: could not generate',
      'de': 'Zusammenfassung: Erstellung fehlgeschlagen', 'it': 'Riepilogo: impossibile generare',
    },
    'summary_failed_snack': {
      'ru': 'Не получилось посчитать саммари', 'es': 'No se pudo generar el resumen', 'fr': 'Impossible de calculer le résumé', 'en': 'Could not compute summary',
      'de': 'Zusammenfassung fehlgeschlagen', 'it': 'Impossibile calcolare il riepilogo',
    },
    'transcription_done_bg': {
      'ru': 'Расшифровка готова — текст сохранён в записи', 'es': 'Transcripción lista — el texto se guardó en la grabación', 'fr': 'Transcription terminée — le texte a été ajouté à l\'enregistrement',
      'en': 'Transcription ready — text saved to the recording',
      'de': 'Transkription fertig — Text in der Aufnahme gespeichert',
      'it': 'Trascrizione pronta — testo salvato nella registrazione',
    },
    'imported': {
      'ru': 'Импортировано: {n}', 'es': 'Importados: {n}', 'fr': 'Importé : {n}', 'en': 'Imported: {n}',
      'de': 'Importiert: {n}', 'it': 'Importati: {n}',
    },
    'imported_errors': {
      'ru': 'Импортировано: {n}, ошибок: {e}', 'es': 'Importados: {n}, errores: {e}', 'fr': 'Importé : {n}, erreurs : {e}',
      'en': 'Imported: {n}, errors: {e}',
      'de': 'Importiert: {n}, Fehler: {e}',
      'it': 'Importati: {n}, errori: {e}',
    },
    'export_format_title': {
      'ru': 'Формат экспорта', 'es': 'Formato de exportación', 'fr': 'Format d\'export', 'en': 'Export format',
      'de': 'Exportformat', 'it': 'Formato di esportazione',
    },
    'export_txt': {
      'ru': 'TXT — текст с таймкодами', 'es': 'TXT — texto con marcas de tiempo', 'fr': 'TXT — texte avec timecodes', 'en': 'TXT — text with timecodes',
      'de': 'TXT — Text mit Zeitcodes', 'it': 'TXT — testo con timecode',
    },
    'export_html': {
      'ru': 'HTML — красивый документ', 'es': 'HTML — documento con formato', 'fr': 'HTML — document élégant', 'en': 'HTML — nice document',
      'de': 'HTML — schönes Dokument', 'it': 'HTML — documento elegante',
    },
    'export_copy': {
      'ru': 'Скопировать текст', 'es': 'Copiar texto', 'fr': 'Copier le texte', 'en': 'Copy text',
      'de': 'Text kopieren', 'it': 'Copia testo',
    },
    'export_pdf': {
      'ru': 'PDF — документ', 'es': 'PDF — documento', 'fr': 'PDF — document', 'en': 'PDF — document',
      'de': 'PDF — Dokument', 'it': 'PDF — documento',
    },
    'export_pdf_error': {
      'ru': 'Ошибка PDF: {e}', 'es': 'Error de PDF: {e}', 'fr': 'Erreur PDF : {e}', 'en': 'PDF error: {e}',
      'de': 'PDF-Fehler: {e}', 'it': 'Errore PDF: {e}',
    },
    'text_copied': {
      'ru': 'Текст скопирован', 'es': 'Texto copiado', 'fr': 'Texte copié', 'en': 'Text copied',
      'de': 'Text kopiert', 'it': 'Testo copiato',
    },
    'share_title': {
      'ru': 'Поделиться', 'es': 'Compartir', 'fr': 'Partager', 'en': 'Share', 'de': 'Teilen', 'it': 'Condividi',
    },
    'share_transcript': {
      'ru': 'Текст транскрипции', 'es': 'Texto de la transcripción', 'fr': 'Texte de la transcription', 'en': 'Transcript text',
      'de': 'Transkripttext', 'it': 'Testo della trascrizione',
    },
    'share_audio': {
      'ru': 'Аудиозапись', 'es': 'Grabación de audio', 'fr': 'Enregistrement audio', 'en': 'Audio recording',
      'de': 'Audioaufnahme', 'it': 'Registrazione audio',
    },
    'send_text_title': {
      'ru': 'Отправить текст', 'es': 'Enviar texto', 'fr': 'Envoyer le texte', 'en': 'Send text',
      'de': 'Text senden', 'it': 'Invia testo',
    },
    'share_pdf_caption': {
      'ru': 'Транскрипция записи в PDF', 'es': 'Transcripción de la grabación en PDF', 'fr': 'Transcription de l\'enregistrement en PDF', 'en': 'Recording transcript as PDF',
      'de': 'Aufnahme-Transkript als PDF', 'it': 'Trascrizione in PDF',
    },
    'rename_title': {
      'ru': 'Переименовать', 'es': 'Renombrar', 'fr': 'Renommer', 'en': 'Rename',
      'de': 'Umbenennen', 'it': 'Rinomina',
    },
    'rename_hint': {
      'ru': 'Название записи...', 'es': 'Nombre de la grabación...', 'fr': 'Nom de l\'enregistrement...', 'en': 'Recording name...',
      'de': 'Name der Aufnahme...', 'it': 'Nome della registrazione...',
    },
    'save': {
      'ru': 'Сохранить', 'es': 'Guardar', 'fr': 'Enregistrer', 'en': 'Save', 'de': 'Speichern', 'it': 'Salva',
    },
    'file_not_found': {
      'ru': 'Файл не найден: {p}', 'es': 'Archivo no encontrado: {p}', 'fr': 'Fichier introuvable : {p}', 'en': 'File not found: {p}',
      'de': 'Datei nicht gefunden: {p}', 'it': 'File non trovato: {p}',
    },
    'platform_error': {
      'ru': 'Ошибка платформы', 'es': 'Error de plataforma', 'fr': 'Erreur de plateforme', 'en': 'Platform error',
      'de': 'Plattformfehler', 'it': 'Errore di piattaforma',
    },
    'error_prefix': {
      'ru': 'Ошибка: {m}', 'es': 'Error: {m}', 'fr': 'Erreur : {m}', 'en': 'Error: {m}',
      'de': 'Fehler: {m}', 'it': 'Errore: {m}',
    },
    'transcribe_error': {
      'ru': 'Ошибка транскрибации: {e}', 'es': 'Error de transcripción: {e}', 'fr': 'Erreur de transcription : {e}', 'en': 'Transcription error: {e}',
      'de': 'Transkriptionsfehler: {e}', 'it': 'Errore di trascrizione: {e}',
    },
    'transcribe_failed': {
      'ru': 'Расшифровка не удалась: {e}', 'es': 'La transcripción falló: {e}', 'fr': 'Échec de la transcription : {e}', 'en': 'Transcription failed: {e}',
      'de': 'Transkription fehlgeschlagen: {e}', 'it': 'Trascrizione non riuscita: {e}',
    },
    // Карточка восстановления
    'recovery_interrupted': {
      'ru': 'Расшифровка прервана', 'es': 'Transcripción interrumpida', 'fr': 'Transcription interrompue', 'en': 'Transcription interrupted',
      'de': 'Transkription unterbrochen', 'it': 'Trascrizione interrotta',
    },
    'recovery_chars': {
      'ru': '{n} символов', 'es': '{n} caracteres', 'fr': '{n} caractères', 'en': '{n} characters',
      'de': '{n} Zeichen', 'it': '{n} caratteri',
    },
    'recovery_chunk': {
      'ru': 'кусок {n}', 'es': 'fragmento {n}', 'fr': 'segment {n}', 'en': 'chunk {n}',
      'de': 'Teil {n}', 'it': 'segmento {n}',
    },
    'recovery_show_text': {
      'ru': 'Показать текст', 'es': 'Mostrar texto', 'fr': 'Afficher le texte', 'en': 'Show text',
      'de': 'Text anzeigen', 'it': 'Mostra testo',
    },
    'recovery_saved_title': {
      'ru': 'Прерванная расшифровка', 'es': 'Transcripción interrumpida', 'fr': 'Transcription interrompue', 'en': 'Interrupted transcription',
      'de': 'Unterbrochene Transkription', 'it': 'Trascrizione interrotta',
    },
    'recovery_resume_hint': {
      'ru': 'Откройте ту же запись и запустите расшифровку — предложим продолжить с места обрыва.', 'es': 'Abre la misma grabación e inicia la transcripción — te ofreceremos continuar desde donde se interrumpió.', 'fr': 'Ouvrez le même enregistrement et lancez la transcription — nous vous proposerons de reprendre là où elle s\'est arrêtée.',
      'en': 'Open the same recording and start transcription — we\'ll offer to continue from where it stopped.',
      'de': 'Öffnen Sie dieselbe Aufnahme und starten Sie die Transkription — wir bieten an, ab der Unterbrechung weiterzumachen.',
      'it': 'Apri la stessa registrazione e avvia la trascrizione — ti offriremo di continuare dal punto di interruzione.',
    },
    // Настройки
    'settings_title': {
      'ru': 'Настройки', 'es': 'Ajustes', 'fr': 'Paramètres', 'en': 'Settings', 'de': 'Einstellungen', 'it': 'Impostazioni',
    },
    'saved': {
      'ru': 'Сохранено', 'es': 'Guardado', 'fr': 'Enregistré', 'en': 'Saved', 'de': 'Gespeichert', 'it': 'Salvato',
    },
    'group_appearance': {
      'ru': 'Оформление', 'es': 'Apariencia', 'fr': 'Apparence', 'en': 'Appearance',
      'de': 'Erscheinungsbild', 'it': 'Aspetto',
    },
    'light_theme': {
      'ru': 'Светлая тема', 'es': 'Tema claro', 'fr': 'Thème clair', 'en': 'Light theme',
      'de': 'Helles Design', 'it': 'Tema chiaro',
    },
    'light_theme_sub': {
      'ru': 'Дневное оформление приложения', 'es': 'Apariencia diurna de la aplicación', 'fr': 'Apparence de jour de l\'application', 'en': 'Daytime appearance',
      'de': 'Tagesaussehen der App', 'it': 'Aspetto diurno dell\'app',
    },
    'group_recording': {
      'ru': 'Запись', 'es': 'Grabación', 'fr': 'Enregistrement', 'en': 'Recording', 'de': 'Aufnahme', 'it': 'Registrazione',
    },
    'sample_rate': {
      'ru': 'Частота дискретизации (Hz)', 'es': 'Frecuencia de muestreo (Hz)', 'fr': 'Fréquence d\'échantillonnage (Hz)', 'en': 'Sample rate (Hz)',
      'de': 'Abtastrate (Hz)', 'it': 'Frequenza di campionamento (Hz)',
    },
    'sample_rate_label': {
      'ru': 'Частота дискретизации', 'es': 'Frecuencia de muestreo', 'fr': 'Fréquence d\'échantillonnage', 'en': 'Sample rate',
      'de': 'Abtastrate', 'it': 'Frequenza di campionamento',
    },
    'bitrate': {
      'ru': 'Битрейт (bps)', 'es': 'Bitrate (bps)', 'fr': 'Débit binaire (bps)', 'en': 'Bitrate (bps)',
      'de': 'Bitrate (bps)', 'it': 'Bitrate (bps)',
    },
    'bitrate_label': {
      'ru': 'Битрейт', 'es': 'Bitrate', 'fr': 'Débit binaire', 'en': 'Bitrate',
      'de': 'Bitrate', 'it': 'Bitrate',
    },
    'channels': {
      'ru': 'Каналы', 'es': 'Canales', 'fr': 'Canaux', 'en': 'Channels', 'de': 'Kanäle', 'it': 'Canali',
    },
    'mono': {
      'ru': 'Моно (1)', 'es': 'Mono (1)', 'fr': 'Mono (1)', 'en': 'Mono (1)', 'de': 'Mono (1)', 'it': 'Mono (1)',
    },
    'stereo': {
      'ru': 'Стерео (2)', 'es': 'Estéreo (2)', 'fr': 'Stéréo (2)', 'en': 'Stereo (2)', 'de': 'Stereo (2)', 'it': 'Stereo (2)',
    },
    'quality_note': {
      'ru': 'Высокие настройки улучшают качество, но увеличивают размер файла. Для расшифровки достаточно 16 кГц, моно.', 'es': 'Los ajustes altos mejoran la calidad, pero aumentan el tamaño del archivo. Para la transcripción basta con 16 kHz, mono.', 'fr': 'Des réglages élevés améliorent la qualité mais augmentent la taille du fichier. Pour la transcription, 16 kHz en mono suffisent.',
      'en': 'Higher settings improve quality but increase file size. For transcription, 16 kHz mono is enough.',
      'de': 'Höhere Einstellungen verbessern die Qualität, vergrößern aber die Datei. Für die Transkription reichen 16 kHz Mono.',
      'it': 'Impostazioni più alte migliorano la qualità ma aumentano le dimensioni. Per la trascrizione bastano 16 kHz, mono.',
    },
    'group_recognition': {
      'ru': 'Распознавание', 'es': 'Reconocimiento', 'fr': 'Reconnaissance', 'en': 'Recognition',
      'de': 'Erkennung', 'it': 'Riconoscimento',
    },
    'engine_on_device': {
      'ru': 'Движок: на устройстве, модель внутри', 'es': 'Motor: en el dispositivo, modelo integrado', 'fr': 'Moteur : sur l\'appareil, modèle intégré',
      'en': 'Engine: on-device, model inside',
      'de': 'Engine: auf dem Gerät, Modell integriert',
      'it': 'Motore: sul dispositivo, modello integrato',
    },
    'engine_on_device_sub': {
      'ru': 'Точная модель GigaAM работает локально. Интернет не нужен, файлы не покидают телефон.', 'es': 'El modelo preciso GigaAM se ejecuta en local. No hace falta internet y los archivos no salen del teléfono.', 'fr': 'Le modèle précis GigaAM fonctionne en local. Pas besoin d\'internet, les fichiers ne quittent pas votre téléphone.',
      'en': 'Accurate GigaAM model runs locally. No internet needed, files never leave your phone.',
      'de': 'Das genaue GigaAM-Modell arbeitet lokal. Kein Internet nötig, Dateien verlassen das Handy nie.',
      'it': 'Il modello accurato GigaAM funziona in locale. Nessun internet, i file non lasciano il telefono.',
    },
    'online_transcribe': {
      'ru': 'Онлайн-расшифровка', 'es': 'Transcripción online', 'fr': 'Transcription en ligne', 'en': 'Online transcription',
      'de': 'Online-Transkription', 'it': 'Trascrizione online',
    },
    'online_transcribe_sub': {
      'ru': 'Точнее локальной модели, но звук уходит на сервер провайдера', 'es': 'Más precisa que el modelo local, pero el audio se envía al servidor del proveedor', 'fr': 'Plus précis que le modèle local, mais l\'audio est envoyé au serveur du fournisseur',
      'en': 'More accurate than the local model, but audio goes to the provider\'s server',
      'de': 'Genauer als das lokale Modell, aber Ton geht an den Server des Anbieters',
      'it': 'Più accurata del modello locale, ma l\'audio va al server del provider',
    },
    'provider': {
      'ru': 'Провайдер', 'es': 'Proveedor', 'fr': 'Fournisseur', 'en': 'Provider', 'de': 'Anbieter', 'it': 'Provider',
    },
    'key_for': {
      'ru': 'Ключ {p}', 'es': 'Clave {p}', 'fr': 'Clé {p}', 'en': 'Key {p}',
      'de': 'Schlüssel {p}', 'it': 'Chiave {p}',
    },
    'key_stored_local': {
      'ru': 'Хранится только на устройстве', 'es': 'Se guarda solo en el dispositivo', 'fr': 'Stockée uniquement sur cet appareil', 'en': 'Stored on this device only',
      'de': 'Nur auf diesem Gerät gespeichert', 'it': 'Salvata solo su questo dispositivo',
    },
    'provider_dialog_title': {
      'ru': 'Провайдер онлайн-транскрипции', 'es': 'Proveedor de transcripción online', 'fr': 'Fournisseur de transcription en ligne', 'en': 'Online transcription provider',
      'de': 'Anbieter für Online-Transkription', 'it': 'Provider di trascrizione online',
    },
    'key_dialog_body': {
      'ru': 'Ключ хранится только на устройстве. Без ключа онлайн-режим выключен — расшифровка идёт офлайн, на устройстве.', 'es': 'La clave se guarda solo en este dispositivo. Sin clave, el modo online está desactivado — la transcripción se realiza offline, en el dispositivo.', 'fr': 'La clé est stockée uniquement sur cet appareil. Sans clé, le mode en ligne est désactivé — la transcription s\'effectue hors ligne, sur l\'appareil.',
      'en': 'The key is stored on this device only. Without a key the online mode is off — transcription runs offline, on the device.',
      'de': 'Der Schlüssel wird nur auf diesem Gerät gespeichert. Ohne Schlüssel ist der Online-Modus aus — die Transkription läuft offline auf dem Gerät.',
      'it': 'La chiave è salvata solo su questo dispositivo. Senza chiave la modalità online è disattivata — la trascrizione avviene offline, sul dispositivo.',
    },
    'paste_api_key': {
      'ru': 'Вставь API-ключ', 'es': 'Pega la clave API', 'fr': 'Collez la clé API', 'en': 'Paste API key',
      'de': 'API-Schlüssel einfügen', 'it': 'Incolla chiave API',
    },
    'key_removed': {
      'ru': 'Ключ удалён', 'es': 'Clave eliminada', 'fr': 'Clé supprimée', 'en': 'Key removed',
      'de': 'Schlüssel entfernt', 'it': 'Chiave rimossa',
    },
    'key_saved': {
      'ru': 'Ключ сохранён', 'es': 'Clave guardada', 'fr': 'Clé enregistrée', 'en': 'Key saved',
      'de': 'Schlüssel gespeichert', 'it': 'Chiave salvata',
    },
    'group_background': {
      'ru': 'Фон и память', 'es': 'Segundo plano y memoria', 'fr': 'Arrière-plan et mémoire', 'en': 'Background & memory',
      'de': 'Hintergrund & Speicher', 'it': 'Sfondo e memoria',
    },
    'miui_unrestricted': {
      'ru': 'Работа без ограничений (MIUI)', 'es': 'Funcionamiento sin restricciones (MIUI)', 'fr': 'Fonctionnement sans restrictions (MIUI)', 'en': 'Unrestricted operation (MIUI)',
      'de': 'Uneingeschränkter Betrieb (MIUI)', 'it': 'Operazione senza restrizioni (MIUI)',
    },
    'miui_sub': {
      'ru': 'Запросить исключение из оптимизации батареи. Без него система может остановить длинную расшифровку в фоне.\nРабота без ограничений: {s}', 'es': 'Solicita la exención de la optimización de batería. Sin ella, el sistema puede detener una transcripción larga en segundo plano.\nFuncionamiento sin restricciones: {s}', 'fr': 'Demandez une exemption de l\'optimisation de la batterie. Sans cela, le système peut arrêter une longue transcription en arrière-plan.\nFonctionnement sans restrictions : {s}',
      'en': 'Request exemption from battery optimization. Without it the system may stop long background transcription.\nUnrestricted operation: {s}',
      'de': 'Ausnahme von der Batterieoptimierung beantragen. Ohne sie kann das System lange Hintergrund-Transkriptionen stoppen.\nUneingeschränkter Betrieb: {s}',
      'it': 'Richiedi l\'esenzione dall\'ottimizzazione della batteria. Senza di essa il sistema può interrompere lunghe trascrizioni in background.\nOperazione senza restrizioni: {s}',
    },
    'miui_checking': {
      'ru': 'проверяю…', 'es': 'comprobando…', 'fr': 'vérification…', 'en': 'checking…',
      'de': 'prüfe…', 'it': 'controllo…',
    },
    'miui_on': {
      'ru': 'включено', 'es': 'activado', 'fr': 'activé', 'en': 'enabled',
      'de': 'aktiviert', 'it': 'attivato',
    },
    'miui_off': {
      'ru': 'не включено', 'es': 'no activado', 'fr': 'non activé', 'en': 'not enabled',
      'de': 'nicht aktiviert', 'it': 'non attivato',
    },
    'miui_manual_path': {
      'ru': 'MIUI: Сведения о батарее → Без ограничений', 'es': 'MIUI: Información de la batería → Sin restricciones', 'fr': 'MIUI : Infos batterie → Sans restrictions',
      'en': 'MIUI: Battery info → Unrestricted',
      'de': 'MIUI: Akku-Info → Uneingeschränkt',
      'it': 'MIUI: Info batteria → Senza restrizioni',
    },
    'enable': {
      'ru': 'Включить', 'es': 'Activar', 'fr': 'Activer', 'en': 'Enable', 'de': 'Aktivieren', 'it': 'Abilita',
    },
    'open_battery_settings': {
      'ru': 'Открыть настройки батареи', 'es': 'Abrir ajustes de batería', 'fr': 'Ouvrir les paramètres de la batterie', 'en': 'Open battery settings',
      'de': 'Batterieeinstellungen öffnen', 'it': 'Apri impostazioni batteria',
    },
    'temp_files': {
      'ru': 'Временные файлы', 'es': 'Archivos temporales', 'fr': 'Fichiers temporaires', 'en': 'Temporary files',
      'de': 'Temporäre Dateien', 'it': 'File temporanei',
    },
    'temp_occupied': {
      'ru': 'Занято: {m} МБ. Обычно мусор удаляется сразу после расшифровки.', 'es': 'Ocupado: {m} MB. Normalmente los archivos temporales se eliminan justo después de la transcripción.', 'fr': 'Occupé : {m} Mo. Les fichiers inutiles sont généralement supprimés juste après la transcription.',
      'en': 'Occupied: {m} MB. Junk is usually removed right after transcription.',
      'de': 'Belegt: {m} MB. Der Müll wird normalerweise direkt nach der Transkription entfernt.',
      'it': 'Occupati: {m} MB. I file temporanei vengono rimossi subito dopo la trascrizione.',
    },
    'temp_none': {
      'ru': 'Временных файлов нет — мусор удаляется сразу после расшифровки.', 'es': 'No hay archivos temporales — se eliminan justo después de la transcripción.', 'fr': 'Aucun fichier temporaire — les fichiers inutiles sont supprimés juste après la transcription.',
      'en': 'No temporary files — junk is removed right after transcription.',
      'de': 'Keine temporären Dateien — der Müll wird direkt nach der Transkription entfernt.',
      'it': 'Nessun file temporaneo — i file vengono rimossi subito dopo la trascrizione.',
    },
    'clear': {
      'ru': 'Очистить', 'es': 'Limpiar', 'fr': 'Vider', 'en': 'Clear', 'de': 'Leeren', 'it': 'Pulisci',
    },
    'freed_mb': {
      'ru': 'Освобождено {m} МБ', 'es': 'Liberados {m} MB', 'fr': '{m} Mo libérés', 'en': 'Freed {m} MB',
      'de': '{m} MB freigegeben', 'it': 'Liberati {m} MB',
    },
    'group_data': {
      'ru': 'Данные', 'es': 'Datos', 'fr': 'Données', 'en': 'Data', 'de': 'Daten', 'it': 'Dati',
    },
    'all_on_device': {
      'ru': 'Всё хранится на устройстве', 'es': 'Todo se guarda en el dispositivo', 'fr': 'Tout est stocké sur l\'appareil', 'en': 'Everything is stored on the device',
      'de': 'Alles wird auf dem Gerät gespeichert', 'it': 'Tutto è archiviato sul dispositivo',
    },
    'all_on_device_sub': {
      'ru': 'Записи, тексты и ключи не покидают телефон без вашего решения.', 'es': 'Las grabaciones, los textos y las claves no salen del teléfono sin tu decisión.', 'fr': 'Enregistrements, textes et clés ne quittent pas votre téléphone sans votre accord.',
      'en': 'Recordings, texts and keys never leave your phone unless you decide so.',
      'de': 'Aufnahmen, Texte und Schlüssel verlassen das Handy nur mit Ihrer Entscheidung.',
      'it': 'Registrazioni, testi e chiavi non lasciano il telefono senza la tua decisione.',
    },
    'share_folder_diag': {
      'ru': 'Папка обмена (диагностика)', 'es': 'Carpeta de intercambio (diagnóstico)', 'fr': 'Dossier d\'échange (diagnostic)', 'en': 'Exchange folder (diagnostics)',
      'de': 'Austauschordner (Diagnose)', 'it': 'Cartella di scambio (diagnostica)',
    },
    'share_folder_sub': {
      'ru': 'Android/data/com.dictapro.app/files — тексты и временные WAV для проверки', 'es': 'Android/data/com.dictapro.app/files — textos y WAV temporales para verificación', 'fr': 'Android/data/com.dictapro.app/files — textes et WAV temporaires pour vérification',
      'en': 'Android/data/com.dictapro.app/files — texts and temporary WAVs for review',
      'de': 'Android/data/com.dictapro.app/files — Texte und temporäre WAVs zur Prüfung',
      'it': 'Android/data/com.dictapro.app/files — testi e WAV temporanei per verifica',
    },
    // Плеер
    'player_title': {
      'ru': 'Прослушивание', 'es': 'Reproducción', 'fr': 'Lecture', 'en': 'Playback',
      'de': 'Wiedergabe', 'it': 'Riproduzione',
    },
    'recording_of': {
      'ru': 'Запись {d}', 'es': 'Grabación {d}', 'fr': 'Enregistrement {d}', 'en': 'Recording {d}',
      'de': 'Aufnahme {d}', 'it': 'Registrazione {d}',
    },
    // Итоги
    'no_transcript': {
      'ru': 'Нет расшифрованного текста для итогов', 'es': 'No hay texto transcrito para el resumen', 'fr': 'Aucun texte transcrit pour le résumé',
      'en': 'No transcribed text for summaries',
      'de': 'Kein transkribierter Text für Zusammenfassungen',
      'it': 'Nessun testo trascritto per i riepiloghi',
    },
    'retry': {
      'ru': 'Повторить', 'es': 'Reintentar', 'fr': 'Réessayer', 'en': 'Retry', 'de': 'Wiederholen', 'it': 'Riprova',
    },
    'load_error': {
      'ru': 'Ошибка загрузки', 'es': 'Error de carga', 'fr': 'Erreur de chargement', 'en': 'Load error',
      'de': 'Ladefehler', 'it': 'Errore di caricamento',
    },
    // Редактор диалога
    'exported_html': {
      'ru': 'HTML экспортирован: {p}', 'es': 'HTML exportado: {p}', 'fr': 'HTML exporté : {p}', 'en': 'HTML exported: {p}',
      'de': 'HTML exportiert: {p}', 'it': 'HTML esportato: {p}',
    },
    'edit_text_title': {
      'ru': 'Редактирование текста', 'es': 'Edición de texto', 'fr': 'Modification du texte', 'en': 'Editing text',
      'de': 'Textbearbeitung', 'it': 'Modifica del testo',
    },
    'saved_to_downloads': {
      'ru': 'Сохранено в папку загрузок', 'es': 'Guardado en Descargas', 'fr': 'Enregistré dans Téléchargements', 'en': 'Saved to Downloads',
      'de': 'Im Download-Ordner gespeichert', 'it': 'Salvato in Download',
    },
    'search_text_hint': {
      'ru': 'Поиск текста...', 'es': 'Buscar en el texto...', 'fr': 'Rechercher du texte...', 'en': 'Search text...',
      'de': 'Text suchen...', 'it': 'Cerca testo...',
    },
    'summary_title': {
      'ru': 'Саммари', 'es': 'Resumen', 'fr': 'Résumé', 'en': 'Summary',
      'de': 'Zusammenfassung', 'it': 'Riepilogo',
    },
    'summary_card_title': {
      'ru': 'Краткое содержание', 'es': 'Resumen breve', 'fr': 'Points clés', 'en': 'Key points',
      'de': 'Kurzfassung', 'it': 'Punti chiave',
    },
    'summary_press_button': {
      'ru': 'Нажмите кнопку ниже для генерации саммари', 'es': 'Pulsa el botón de abajo para generar un resumen', 'fr': 'Appuyez sur le bouton ci-dessous pour générer un résumé',
      'en': 'Press the button below to generate a summary',
      'de': 'Taste unten drücken, um eine Zusammenfassung zu erzeugen',
      'it': 'Premi il pulsante qui sotto per generare il riepilogo',
    },
    'no_summary_yet': {
      'ru': 'Нет доступного резюме', 'es': 'No hay resumen disponible', 'fr': 'Aucun résumé disponible', 'en': 'No summary available',
      'de': 'Keine Zusammenfassung verfügbar', 'it': 'Nessun riepilogo disponibile',
    },
    'copied_to_clipboard': {
      'ru': 'Скопировано в буфер обмена', 'es': 'Copiado al portapapeles', 'fr': 'Copié dans le presse-papiers', 'en': 'Copied to clipboard',
      'de': 'In die Zwischenablage kopiert', 'it': 'Copiato negli appunti',
    },
    'html_saved': {
      'ru': 'HTML сохранён: {p}', 'es': 'HTML guardado: {p}', 'fr': 'HTML enregistré : {p}', 'en': 'HTML saved: {p}',
      'de': 'HTML gespeichert: {p}', 'it': 'HTML salvato: {p}',
    },
    'edit_dialog_title': {
      'ru': 'Редактировать диалог', 'es': 'Editar diálogo', 'fr': 'Modifier le dialogue', 'en': 'Edit dialogue',
      'de': 'Dialog bearbeiten', 'it': 'Modifica dialogo',
    },
    'enter_text_hint': {
      'ru': 'Введите текст...', 'es': 'Escribe el texto...', 'fr': 'Saisissez le texte...', 'en': 'Enter text...',
      'de': 'Text eingeben...', 'it': 'Inserisci testo...',
    },
    // ---------- Task 065: экран «Подписка» ----------
    'sub_settings_item': {
      'ru': 'Подписка', 'es': 'Suscripción', 'fr': 'Abonnement', 'en': 'Subscription',
      'de': 'Abo', 'it': 'Abbonamento',
    },
    'sub_all_plans': {
      'ru': 'Все тарифы и пакеты', 'es': 'Todos los planes y paquetes', 'fr': 'Toutes les formules et packs', 'en': 'All plans and packs',
      'de': 'Alle Tarife und Pakete', 'it': 'Tutti i piani e i pacchetti',
    },
    'sub_row_title': {
      'ru': 'Подписка и ИИ-часы', 'es': 'Suscripción y horas de IA', 'fr': 'Abonnement et heures IA', 'en': 'Subscription & AI hours',
      'de': 'Abo & KI-Stunden', 'it': 'Abbonamento e ore AI',
    },
    'sub_settings_sub': {
      'ru': 'Тарифы, ИИ-часы, пакеты', 'es': 'Planes, horas de IA, paquetes', 'fr': 'Formules, heures IA, packs',
      'en': 'Plans, AI hours, packs',
      'de': 'Tarife, KI-Stunden, Pakete',
      'it': 'Piani, ore AI, pacchetti',
    },
    'sub_title': {
      'ru': 'Подписка', 'es': 'Suscripción', 'fr': 'Abonnement', 'en': 'Subscription',
      'de': 'Abo', 'it': 'Abbonamento',
    },
    'sub_status_none': {
      'ru': 'Активной подписки нет — доступен бесплатный режим', 'es': 'No hay suscripción activa — modo gratuito disponible', 'fr': 'Aucun abonnement actif — mode gratuit disponible',
      'en': 'No active subscription — free mode available',
      'de': 'Kein aktives Abo — Gratismodus verfügbar',
      'it': 'Nessun abbonamento attivo — disponibile la modalità gratuita',
    },
    'sub_status_tier': {
      'ru': 'Тариф: {t}', 'es': 'Plan: {t}', 'fr': 'Formule : {t}', 'en': 'Plan: {t}',
      'de': 'Tarif: {t}', 'it': 'Piano: {t}',
    },
    'sub_status_balance': {
      'ru': 'ИИ-часы: {h} ч', 'es': 'Horas de IA: {h} h', 'fr': 'Heures IA : {h} h', 'en': 'AI hours: {h} h',
      'de': 'KI-Stunden: {h} h', 'it': 'Ore AI: {h} h',
    },
    'sub_status_next': {
      'ru': 'Списание и продление — в магазине приложений', 'es': 'El cobro y la renovación se gestionan en la tienda de aplicaciones', 'fr': 'Facturation et renouvellement dans la boutique d\'applications',
      'en': 'Billing and renewal are handled by the app store',
      'de': 'Abrechnung und Verlängerung über den App-Store',
      'it': 'Addebito e rinnovo gestiti dall\'app store',
    },
    'sub_full_unlock_status': {
      'ru': 'Полная версия куплена — дневной лимит расшифровки снят', 'es': 'Versión completa comprada — límite diario de transcripción eliminado', 'fr': 'Version complète achetée — limite quotidienne de transcription levée',
      'en': 'Full version purchased — daily transcription limit removed',
      'de': 'Vollversion gekauft — tägliches Transkriptionslimit aufgehoben',
      'it': 'Versione completa acquistata — limite giornaliero rimosso',
    },
    'sub_period_month': {
      'ru': 'Месяц', 'es': 'Mes', 'fr': 'Mois', 'en': 'Month',
      'de': 'Monat', 'it': 'Mese',
    },
    'sub_period_year': {
      'ru': 'Год', 'es': 'Año', 'fr': 'Année', 'en': 'Year',
      'de': 'Jahr', 'it': 'Anno',
    },
    'sub_tier_diary': {
      'ru': 'Дневник', 'es': 'Diario', 'fr': 'Journal', 'en': 'Diary',
      'de': 'Tagebuch', 'it': 'Diario',
    },
    'sub_tier_assistant': {
      'ru': 'Ассистент', 'es': 'Asistente', 'fr': 'Assistant', 'en': 'Assistant',
      'de': 'Assistent', 'it': 'Assistente',
    },
    'sub_tier_unlimited': {
      'ru': 'Безлимит', 'es': 'Ilimitado', 'fr': 'Illimité', 'en': 'Unlimited',
      'de': 'Unbegrenzt', 'it': 'Illimitato',
    },
    'sub_tier_diary_desc': {
      'ru': '10 ИИ-часов в месяц для онлайн-итогов', 'es': '10 horas de IA al mes para resúmenes online', 'fr': '10 heures IA par mois pour les résumés en ligne',
      'en': '10 AI hours per month for online summaries',
      'de': '10 KI-Stunden pro Monat für Online-Zusammenfassungen',
      'it': '10 ore AI al mese per riepiloghi online',
    },
    'sub_tier_assistant_desc': {
      'ru': '20 ИИ-часов в месяц для онлайн-итогов', 'es': '20 horas de IA al mes para resúmenes online', 'fr': '20 heures IA par mois pour les résumés en ligne',
      'en': '20 AI hours per month for online summaries',
      'de': '20 KI-Stunden pro Monat für Online-Zusammenfassungen',
      'it': '20 ore AI al mese per riepiloghi online',
    },
    'sub_tier_unlimited_desc': {
      'ru': '40 ИИ-часов в месяц для онлайн-итогов', 'es': '40 horas de IA al mes para resúmenes online', 'fr': '40 heures IA par mois pour les résumés en ligne',
      'en': '40 AI hours per month for online summaries',
      'de': '40 KI-Stunden pro Monat für Online-Zusammenfassungen',
      'it': '40 ore AI al mese per riepiloghi online',
    },
    'sub_current_badge': {
      'ru': 'Текущий тариф', 'es': 'Plan actual', 'fr': 'Formule actuelle', 'en': 'Current plan',
      'de': 'Aktueller Tarif', 'it': 'Piano attuale',
    },
    'sub_price_pending': {
      'ru': 'Цена появится после запуска в магазине', 'es': 'El precio aparecerá cuando la app esté disponible en la tienda', 'fr': 'Le prix apparaîtra après le lancement en boutique',
      'en': 'Price will appear once the app is live in the store',
      'de': 'Preis erscheint nach dem Start im Store',
      'it': 'Il prezzo apparirà dopo il lancio sullo store',
    },
    'sub_store_banner': {
      'ru': 'Покупки станут доступны после публикации приложения в магазине. Тарифы уже видны — цены подтянутся автоматически.', 'es': 'Las compras estarán disponibles cuando la aplicación se publique en la tienda. Los planes ya se muestran — los precios se cargarán automáticamente.', 'fr': 'Les achats seront disponibles après la publication de l\'application en boutique. Les formules sont déjà visibles — les prix se chargeront automatiquement.',
      'en': 'Purchases will become available once the app is published in the store. Plans are already listed — prices will load automatically.',
      'de': 'Käufe werden nach Veröffentlichung der App im Store verfügbar. Tarife sind bereits sichtbar — Preise werden automatisch geladen.',
      'it': 'Gli acquisti saranno disponibili dopo la pubblicazione dell\'app sullo store. I piani sono già visibili — i prezzi verranno caricati automaticamente.',
    },
    'sub_packs_title': {
      'ru': 'Пакеты ИИ-часов', 'es': 'Paquetes de horas de IA', 'fr': 'Packs d\'heures IA', 'en': 'AI hour packs',
      'de': 'KI-Stundenpakete', 'it': 'Pacchetti di ore AI',
    },
    'sub_packs_note': {
      'ru': 'Не сгорают. Тратятся после включённых часов подписки.', 'es': 'No caducan. Se consumen después de las horas incluidas en la suscripción.', 'fr': 'N\'expirent jamais. Débités après les heures incluses dans l\'abonnement.',
      'en': 'Never expire. Spent after the subscription\'s included hours.',
      'de': 'Verfallen nicht. Werden nach den Abo-Stunden verbraucht.',
      'it': 'Non scadono. Utilizzate dopo le ore incluse nell\'abbonamento.',
    },
    'sub_pack_hours': {
      'ru': '{n} ИИ-часов', 'es': '{n} horas de IA', 'fr': '{n} heures IA', 'en': '{n} AI hours',
      'de': '{n} KI-Stunden', 'it': '{n} ore AI',
    },
    'sub_buy': {
      'ru': 'Оформить', 'es': 'Suscribirse', 'fr': 'S\'abonner', 'en': 'Subscribe',
      'de': 'Abschließen', 'it': 'Attiva',
    },
    'sub_buy_pack': {
      'ru': 'Купить', 'es': 'Comprar', 'fr': 'Acheter', 'en': 'Buy',
      'de': 'Kaufen', 'it': 'Acquista',
    },
    'sub_restore': {
      'ru': 'Восстановить покупку', 'es': 'Restaurar compra', 'fr': 'Restaurer l\'achat', 'en': 'Restore purchase',
      'de': 'Kauf wiederherstellen', 'it': 'Ripristina acquisto',
    },
    'sub_promo': {
      'ru': 'Ввести промокод', 'es': 'Introducir código promocional', 'fr': 'Saisir un code promo', 'en': 'Enter promo code',
      'de': 'Promocode eingeben', 'it': 'Inserisci codice promo',
    },
    'sub_promo_title': {
      'ru': 'Промокод', 'es': 'Código promocional', 'fr': 'Code promo', 'en': 'Promo code',
      'de': 'Promocode', 'it': 'Codice promo',
    },
    'sub_promo_hint': {
      'ru': 'Код из письма или поста', 'es': 'Código de un correo o una publicación', 'fr': 'Code reçu par e-mail ou dans une publication', 'en': 'Code from an email or post',
      'de': 'Code aus E-Mail oder Beitrag', 'it': 'Codice da email o post',
    },
    'sub_promo_pending': {
      'ru': 'Промокоды заработают после публикации приложения.', 'es': 'Los códigos promocionales funcionarán cuando la aplicación se publique.', 'fr': 'Les codes promo fonctionneront après la publication de l\'application.',
      'en': 'Promo codes will work once the app is published.',
      'de': 'Promocodes funktionieren nach Veröffentlichung der App.',
      'it': 'I codici promo funzioneranno dopo la pubblicazione dell\'app.',
    },
    'sub_purchased': {
      'ru': 'Готово! Покупка применена.', 'es': '¡Listo! Compra aplicada.', 'fr': 'Terminé ! Achat appliqué.', 'en': 'Done! Purchase applied.',
      'de': 'Fertig! Kauf angewendet.', 'it': 'Fatto! Acquisto applicato.',
    },
    'sub_year_hint': {
      'ru': 'год', 'es': 'año', 'fr': 'an', 'en': 'year',
      'de': 'Jahr', 'it': 'anno',
    },
    'sub_month_hint': {
      'ru': 'мес', 'es': 'mes', 'fr': 'mois', 'en': 'mo',
      'de': 'Mon.', 'it': 'mese',
    },
    // ---------- Task 068: экран «Итоги» (V3-редизайн) ----------
    'summary_subtitle': {
      'ru': 'конспект из текста записи', 'es': 'síntesis del texto de la grabación', 'fr': 'Synthèse du texte de l\'enregistrement', 'en': 'digest of the recording text',
      'de': 'Konspekt aus dem Aufnahmetext', 'it': 'sintesi dal testo della registrazione',
    },
    'summary_mode_local': {
      'ru': 'Локально', 'es': 'Local', 'fr': 'En local', 'en': 'On-device',
      'de': 'Lokal', 'it': 'Locale',
    },
    'summary_mode_local_sub': {
      'ru': 'без интернета', 'es': 'sin internet', 'fr': 'sans internet', 'en': 'no internet',
      'de': 'ohne Internet', 'it': 'senza internet',
    },
    'summary_mode_online': {
      'ru': 'Онлайн', 'es': 'Online', 'fr': 'En ligne', 'en': 'Online',
      'de': 'Online', 'it': 'Online',
    },
    'summary_mode_online_sub': {
      'ru': 'точнее · ИИ-часы', 'es': 'más preciso · horas de IA', 'fr': 'plus précis · heures IA', 'en': 'smarter · AI hours',
      'de': 'genauer · KI-Stunden', 'it': 'più preciso · ore AI',
    },
    'summary_block_deal': {
      'ru': 'О ЧЁМ ДОГОВОРИЛИСЬ', 'es': 'LO QUE SE ACORDÓ', 'fr': 'CE QUI A ÉTÉ CONVENU', 'en': 'WHAT WAS AGREED',
      'de': 'WAS VEREINBART WURDE', 'it': 'COSA È STATO CONCORDATO',
    },
    'summary_block_tasks': {
      'ru': 'ЗАДАЧИ', 'es': 'TAREAS', 'fr': 'TÂCHES', 'en': 'TASKS',
      'de': 'AUFGABEN', 'it': 'ATTIVITÀ',
    },
    'summary_block_figures': {
      'ru': 'ЦИФРЫ И ДАТЫ', 'es': 'CIFRAS Y FECHAS', 'fr': 'CHIFFRES ET DATES', 'en': 'NUMBERS & DATES',
      'de': 'ZAHLEN & DATEN', 'it': 'NUMERI E DATE',
    },
    'summary_note': {
      'ru': 'Онлайн-итоги считаются на сервере за ИИ-часы и кэшируются: повторный показ — бесплатно. Локальные итоги работают без интернета.', 'es': 'Los resúmenes online se calculan en el servidor a cambio de horas de IA y se guardan en caché: volver a verlos es gratis. Los resúmenes locales funcionan sin internet.', 'fr': 'Les résumés en ligne sont calculés sur le serveur et décomptés en heures IA, puis mis en cache : les revoir est gratuit. Les résumés locaux fonctionnent sans internet.',
      'en': 'Online summaries run on the server against AI hours and are cached: showing them again is free. On-device summaries work without internet.',
      'de': 'Online-Zusammenfassungen laufen auf dem Server für KI-Stunden und werden gecacht: erneutes Anzeigen ist kostenlos. Lokale Zusammenfassungen funktionieren ohne Internet.',
      'it': 'I riepiloghi online vengono elaborati sul server in cambio di ore AI e sono memorizzati in cache: rivederli è gratuito. I riepiloghi locali funzionano senza internet.',
    },
    'online_summary_not_yet': {
      'ru': 'Онлайн-итоги ещё не собраны. Нажмите «Обновить», чтобы запросить их.', 'es': 'Los resúmenes online aún no están listos. Pulsa «Actualizar» para solicitarlos.', 'fr': 'Les résumés en ligne ne sont pas encore prêts. Appuyez sur « Actualiser » pour les demander.',
      'en': 'Online summaries are not ready yet. Tap "Refresh" to request them.',
      'de': 'Online-Zusammenfassungen fehlen noch. Tippen Sie auf „Aktualisieren“, um sie anzufordern.',
      'it': 'I riepiloghi online non sono ancora pronti. Tocca "Aggiorna" per richiederli.',
    },
    'summary_full_text': {
      'ru': 'Полный текст', 'es': 'Texto completo', 'fr': 'Texte complet', 'en': 'Full text',
      'de': 'Volltext', 'it': 'Testo completo',
    },
    // ---------- Task 068: экран «Диалог» ----------
    'dialogue_title': {
      'ru': 'Диалог', 'es': 'Diálogo', 'fr': 'Dialogue', 'en': 'Dialogue',
      'de': 'Dialog', 'it': 'Dialogo',
    },
    'dialogue_subtitle': {
      'ru': 'Реплик: {n} · говорящих: {s} · разметка вручную', 'es': 'Intervenciones: {n} · hablantes: {s} · marcado manual', 'fr': 'Répliques : {n} · locuteurs : {s} · annotation manuelle',
      'en': '{n} lines · {s} speakers · manual markup',
      'de': '{n} Zeilen · {s} Sprecher · manuelle Markierung',
      'it': '{n} righe · {s} parlanti · annotazione manuale',
    },
    'dialogue_speaker': {
      'ru': 'ГОВОРЯЩИЙ {n}', 'es': 'HABLANTE {n}', 'fr': 'LOCUTEUR {n}', 'en': 'SPEAKER {n}',
      'de': 'SPRECHER {n}', 'it': 'PARLANTE {n}',
    },
    'dialogue_tool_speaker': {
      'ru': 'Поменять говорящего', 'es': 'Cambiar hablante', 'fr': 'Changer de locuteur', 'en': 'Change speaker',
      'de': 'Sprecher wechseln', 'it': 'Cambia parlante',
    },
    'dialogue_tool_split': {
      'ru': 'Разделить', 'es': 'Dividir', 'fr': 'Diviser', 'en': 'Split',
      'de': 'Teilen', 'it': 'Dividi',
    },
    'dialogue_tool_merge': {
      'ru': 'Объединить', 'es': 'Unir', 'fr': 'Fusionner', 'en': 'Merge',
      'de': 'Zusammenführen', 'it': 'Unisci',
    },
    'dialogue_footnote': {
      'ru': 'Разметка хранится только в телефоне. Экспорт может включать или не включать подписи говорящих.', 'es': 'El marcado se guarda solo en el teléfono. La exportación puede incluir o no las etiquetas de los hablantes.', 'fr': 'L\'annotation est stockée uniquement sur votre téléphone. L\'export peut inclure ou non les étiquettes des locuteurs.',
      'en': 'Markup is stored on your phone only. Exports may include speaker labels or not.',
      'de': 'Die Markierung bleibt nur auf dem Telefon. Exporte können Sprecherbezeichnungen enthalten oder auch nicht.',
      'it': 'Le annotazioni restano solo sul telefono. Le esportazioni possono includere o meno le etichette dei parlanti.',
    },
    // ---------- Task 068: экран «Прослушивание» ----------
    'player_seek_section': {
      'ru': 'Текст и переход к месту', 'es': 'Texto y salto a la posición', 'fr': 'Texte et saut vers la position', 'en': 'Text and jump to position',
      'de': 'Text und Sprung zur Stelle', 'it': 'Testo e salto al punto',
    },
    'player_seek_hint': {
      'ru': 'нажмите строку — плеер прыгнет', 'es': 'pulsa una línea — el reproductor saltará', 'fr': 'appuyez sur une ligne — le lecteur saute à cet endroit', 'en': 'tap a line — the player jumps',
      'de': 'Zeile antippen — der Player springt', 'it': 'tocca una riga — il player salta',
    },
    'player_segment_of': {
      'ru': 'реплика {i} из {n}', 'es': 'intervención {i} de {n}', 'fr': 'réplique {i} sur {n}', 'en': 'segment {i} of {n}',
      'de': 'Abschnitt {i} von {n}', 'it': 'segmento {i} di {n}',
    },

    // ---------- Task 068-1: полная локализация остатка UI ----------
    'nav_recordings': {
      'ru': 'Записи', 'en': 'Recordings', 'de': 'Aufnahmen',
      'fr': 'Enregistrements', 'es': 'Grabaciones', 'it': 'Registrazioni',
    },
    'nav_texts': {
      'ru': 'Тексты', 'en': 'Texts', 'de': 'Texte',
      'fr': 'Textes', 'es': 'Textos', 'it': 'Testi',
    },
    'nav_summaries': {
      'ru': 'Итоги', 'en': 'Summaries', 'de': 'Zusammenfassungen',
      'fr': 'Résumés', 'es': 'Resúmenes', 'it': 'Riepiloghi',
    },
    'nav_more': {
      'ru': 'Ещё', 'en': 'More', 'de': 'Mehr',
      'fr': 'Plus', 'es': 'Más', 'it': 'Altro',
    },
    'more_subtitle': {
      'ru': 'Настройки, подписка, справка и служебное', 'en': 'Settings, subscription, help and tools', 'de': 'Einstellungen, Abo, Hilfe und Extras',
      'fr': 'Réglages, abonnement, aide et outils', 'es': 'Ajustes, suscripción, ayuda y herramientas', 'it': 'Impostazioni, abbonamento, aiuto e strumenti',
    },
    'more_settings_sub': {
      'ru': 'оформление · запись · распознавание · фон · данные', 'en': 'appearance · recording · recognition · background · data', 'de': 'Design · Aufnahme · Erkennung · Hintergrund · Daten',
      'fr': 'apparence · enregistrement · reconnaissance · arrière-plan · données', 'es': 'apariencia · grabación · reconocimiento · fondo · datos', 'it': 'aspetto · registrazione · riconoscimento · sfondo · dati',
    },
    'more_subscription_sub': {
      'ru': 'тарифы, пакеты часов, промокод, восстановление', 'en': 'plans, hour packs, promo code, restore', 'de': 'Tarife, Stundenpakete, Promocode, Wiederherstellung',
      'fr': 'formules, packs d\'heures, code promo, restauration', 'es': 'planes, paquetes de horas, código promo, restauración', 'it': 'piani, pacchetti ore, codice promo, ripristino',
    },
    'more_privacy_note': {
      'ru': 'Всё хранится на устройстве: записи, тексты и ключи не покидают телефон.', 'en': 'Everything stays on the device: recordings, texts and keys never leave your phone.', 'de': 'Alles bleibt auf dem Gerät: Aufnahmen, Texte und Schlüssel verlassen das Handy nie.',
      'fr': 'Tout reste sur l\'appareil : enregistrements, textes et clés ne quittent jamais votre téléphone.', 'es': 'Todo se queda en el dispositivo: las grabaciones, los textos y las claves no salen del teléfono.', 'it': 'Tutto resta sul dispositivo: registrazioni, testi e chiavi non lasciano mai il telefono.',
    },
    'help_title': {
      'ru': 'Как пользоваться', 'en': 'How to use', 'de': 'So funktioniert es',
      'fr': 'Mode d\'emploi', 'es': 'Cómo usar', 'it': 'Come si usa',
    },
    'help_row_sub': {
      'ru': 'короткие подсказки по записи и расшифровке', 'en': 'short tips on recording and transcription', 'de': 'kurze Tipps zu Aufnahme und Transkription',
      'fr': 'astuces courtes : enregistrement et transcription', 'es': 'consejos breves sobre grabación y transcripción', 'it': 'brevi consigli su registrazione e trascrizione',
    },
    'help_record_sub': {
      'ru': 'Нажмите круглую кнопку. Можно свернуть приложение — запись продолжится в фоне. Таймер сна остановит её сам.', 'en': 'Tap the round button. You can minimize the app — recording continues in the background. The sleep timer will stop it for you.', 'de': 'Tippen Sie auf die runde Taste. Die App darf minimiert werden — die Aufnahme läuft im Hintergrund weiter. Der Schlaf-Timer stoppt sie automatisch.',
      'fr': 'Appuyez sur le bouton rond. Vous pouvez réduire l\'application — l\'enregistrement continue en arrière-plan. Le minuteur de veille l\'arrêtera tout seul.', 'es': 'Pulsa el botón redondo. Puedes minimizar la aplicación — la grabación continúa en segundo plano. El temporizador de apagado la detiene solo.', 'it': 'Tocca il pulsante rotondo. Puoi ridurre l\'app — la registrazione continua in background. Il timer di spegnimento la ferma da solo.',
    },
    'help_import_title': {
      'ru': 'Импорт готовых файлов', 'en': 'Import files', 'de': 'Dateien importieren',
      'fr': 'Importer des fichiers', 'es': 'Importar archivos', 'it': 'Importa file',
    },
    'help_import_sub': {
      'ru': 'Кнопка «Импорт» — выберите mp3, m4a, wav и другие. Приложение расшифрует их на устройстве.', 'en': 'Use the "Import" button — pick mp3, m4a, wav and others. The app transcribes them on the device.', 'de': 'Taste „Importieren“ — wählen Sie mp3, m4a, wav und weitere. Die App transkribiert sie auf dem Gerät.',
      'fr': 'Bouton « Importer » — choisissez mp3, m4a, wav et autres. L\'application les transcrira sur l\'appareil.', 'es': 'Botón «Importar» — elige mp3, m4a, wav y otros. La app los transcribe en el dispositivo.', 'it': 'Pulsante «Importa» — scegli mp3, m4a, wav e altri. L\'app li trascrive sul dispositivo.',
    },
    'help_transcribe_title': {
      'ru': 'Расшифровка', 'en': 'Transcription', 'de': 'Transkription',
      'fr': 'Transcription', 'es': 'Transcripción', 'it': 'Trascrizione',
    },
    'help_transcribe_sub': {
      'ru': 'Считается прямо в телефоне, интернет не нужен. Длинную запись можно продолжить с места обрыва.', 'en': 'Runs right on your phone, no internet needed. A long recording can be resumed from where it stopped.', 'de': 'Läuft direkt auf dem Handy, kein Internet nötig. Eine lange Aufnahme kann ab der Unterbrechung fortgesetzt werden.',
      'fr': 'Calculé directement sur le téléphone, sans internet. Un long enregistrement peut reprendre là où il s\'est arrêté.', 'es': 'Se procesa directamente en el teléfono, sin internet. Una grabación larga puede continuarse desde donde se interrumpió.', 'it': 'Elaborata direttamente sul telefono, senza internet. Una registrazione lunga può riprendere dal punto di interruzione.',
    },
    'help_text_title': {
      'ru': 'Текст и диалог', 'en': 'Text & dialogue', 'de': 'Text & Dialog',
      'fr': 'Texte et dialogue', 'es': 'Texto y diálogo', 'it': 'Testo e dialogo',
    },
    'help_text_sub': {
      'ru': 'Текст можно править, разделять по говорящим, искать по словам и копировать.', 'en': 'You can edit the text, split it by speakers, search by words and copy.', 'de': 'Der Text lässt sich bearbeiten, nach Sprechern trennen, durchsuchen und kopieren.',
      'fr': 'Le texte peut être modifié, divisé par locuteurs, recherché par mots et copié.', 'es': 'El texto se puede editar, dividir por hablantes, buscar por palabras y copiar.', 'it': 'Il testo si può modificare, dividere per parlanti, cercare per parole e copiare.',
    },
    'help_summary_sub': {
      'ru': 'Локально — быстро и без сети. Онлайн — точнее, расходует ИИ-часы и повторно показывается бесплатно из кэша.', 'en': 'On-device — fast and offline. Online — more accurate, spends AI hours, and replays are free from cache.', 'de': 'Lokal — schnell und offline. Online — genauer, verbraucht KI-Stunden, erneute Anzeige gratis aus dem Cache.',
      'fr': 'En local — rapide et hors ligne. En ligne — plus précis, consomme des heures IA, réaffichage gratuit depuis le cache.', 'es': 'Local — rápido y sin conexión. Online — más preciso, consume horas de IA y se muestra de nuevo gratis desde la caché.', 'it': 'In locale — veloce e offline. Online — più preciso, consuma ore AI e la riproduzione è gratis dalla cache.',
    },
    'help_export_title': {
      'ru': 'Экспорт и отправка', 'en': 'Export & share', 'de': 'Export & Senden',
      'fr': 'Export et envoi', 'es': 'Exportar y enviar', 'it': 'Esporta e invia',
    },
    'help_export_sub': {
      'ru': 'TXT с таймкодами, HTML, PDF — или сразу отправить в мессенджер.', 'en': 'TXT with timecodes, HTML, PDF — or send straight to a messenger.', 'de': 'TXT mit Zeitcodes, HTML, PDF — oder direkt an einen Messenger senden.',
      'fr': 'TXT avec timecodes, HTML, PDF — ou envoi direct vers une messagerie.', 'es': 'TXT con marcas de tiempo, HTML, PDF — o enviar directamente a un mensajero.', 'it': 'TXT con timecode, HTML, PDF — o invia subito a un messenger.',
    },
    'about_title': {
      'ru': 'О приложении', 'en': 'About', 'de': 'Über die App',
      'fr': 'À propos', 'es': 'Acerca de', 'it': 'Informazioni',
    },
    'about_row_sub': {
      'ru': 'что считается на устройстве, лицензии, политика', 'en': 'what runs on-device, licenses, policy', 'de': 'was auf dem Gerät läuft, Lizenzen, Richtlinien',
      'fr': 'ce qui tourne en local, licences, politique', 'es': 'qué se procesa en el dispositivo, licencias, políticas', 'it': 'cosa gira in locale, licenze, policy',
    },
    'about_p1': {
      'ru': 'ДиктаПро превращает речь в текст на самом телефоне. Запись, расшифровка, поиск и итоги считаются на устройстве; модель распознавания хранится внутри приложения.', 'en': 'DictaPro turns speech into text right on your phone. Recording, transcription, search and summaries run on the device; the speech model is stored inside the app.', 'de': 'DictaPro verwandelt Sprache direkt auf dem Handy in Text. Aufnahme, Transkription, Suche und Zusammenfassungen laufen auf dem Gerät; das Spracherkennungsmodell steckt in der App.',
      'fr': 'DictaPro transforme la parole en texte directement sur votre téléphone. Enregistrement, transcription, recherche et résumés sont calculés sur l\'appareil ; le modèle de reconnaissance est intégré à l\'application.', 'es': 'DictaPro convierte la voz en texto directamente en tu teléfono. La grabación, la transcripción, la búsqueda y los resúmenes se procesan en el dispositivo; el modelo de reconocimiento va dentro de la aplicación.', 'it': 'DictaPro trasforma la voce in testo direttamente sul telefono. Registrazione, trascrizione, ricerca e riepiloghi sono elaborati sul dispositivo; il modello di riconoscimento è integrato nell\'app.',
    },
    'about_p2': {
      'ru': 'Онлайн-расшифровка и онлайн-итоги выключены по умолчанию и включаются только вашим решением: тогда текст записи уходит на выбранный вами сервис по защищённому соединению.', 'en': 'Online transcription and online summaries are off by default and only enabled by your choice: then the recording text goes to the service you pick over a secure connection.', 'de': 'Online-Transkription und Online-Zusammenfassungen sind standardmäßig aus und werden nur auf Ihre Entscheidung aktiviert: dann geht der Aufnahmetext über eine gesicherte Verbindung an den von Ihnen gewählten Dienst.',
      'fr': 'La transcription et les résumés en ligne sont désactivés par défaut et ne s\'activent que sur votre décision : le texte de l\'enregistrement part alors vers le service de votre choix via une connexion sécurisée.', 'es': 'La transcripción y los resúmenes online están desactivados por defecto y solo se activan por tu decisión: entonces el texto de la grabación se envía al servicio que elijas por conexión segura.', 'it': 'Trascrizione e riepiloghi online sono disattivati per impostazione predefinita e si attivano solo su tua decisione: il testo della registrazione va al servizio che scegli su connessione sicura.',
    },
    'about_licenses_title': {
      'ru': 'Лицензии', 'en': 'Licenses', 'de': 'Lizenzen',
      'fr': 'Licences', 'es': 'Licencias', 'it': 'Licenze',
    },
    'about_licenses_body': {
      'ru': 'Шрифты Onest и JetBrains Mono — SIL Open Font License 1.1.\nМодель распознавания GigaAM — по лицензии правообладателя (см. карточку модели).', 'en': 'Fonts Onest and JetBrains Mono — SIL Open Font License 1.1.\nSpeech model GigaAM — under the rights holder\'s license (see the model card).', 'de': 'Schriften Onest und JetBrains Mono — SIL Open Font License 1.1.\nSprachmodell GigaAM — unter der Lizenz des Rechteinhabers (siehe Modellkarte).',
      'fr': 'Polices Onest et JetBrains Mono — SIL Open Font License 1.1.\nModèle de reconnaissance GigaAM — sous licence du titulaire des droits (voir la fiche du modèle).', 'es': 'Fuentes Onest y JetBrains Mono — SIL Open Font License 1.1.\nModelo de reconocimiento GigaAM — bajo la licencia del titular (ver la ficha del modelo).', 'it': 'Font Onest e JetBrains Mono — SIL Open Font License 1.1.\nModello di riconoscimento GigaAM — con licenza del titolare (vedi la scheda del modello).',
    },
    'about_privacy_title': {
      'ru': 'Приватность', 'en': 'Privacy', 'de': 'Datenschutz',
      'fr': 'Confidentialité', 'es': 'Privacidad', 'it': 'Privacy',
    },
    'about_privacy_body': {
      'ru': 'Рекламы нет, рекламный идентификатор не используется, аккаунт не нужен. Удаление записей и всех данных — средствами приложения или системы.', 'en': 'No ads, no advertising ID, no account needed. Recordings and all data can be deleted via the app or the system.', 'de': 'Keine Werbung, keine Werbe-ID, kein Konto nötig. Aufnahmen und alle Daten lassen sich über die App oder das System löschen.',
      'fr': 'Pas de publicité, pas d\'identifiant publicitaire, pas de compte. Les enregistrements et toutes les données se suppriment via l\'application ou le système.', 'es': 'Sin anuncios, sin identificador publicitario, sin cuenta. Las grabaciones y todos los datos se borran desde la aplicación o el sistema.', 'it': 'Niente pubblicità, nessun identificatore pubblicitario, nessun account. Registrazioni e dati si eliminano dall\'app o dal sistema.',
    },
    'share_folder_row_sub': {
      'ru': 'тексты и временные файлы для проверки', 'en': 'texts and temp files for review', 'de': 'Texte und temporäre Dateien zur Prüfung',
      'fr': 'textes et fichiers temporaires pour vérification', 'es': 'textos y archivos temporales para revisión', 'it': 'testi e file temporanei per la verifica',
    },
    'diag_dialog_body': {
      'ru': 'Android/data/com.dictapro.app/files\n\nЗдесь лежат тексты и временные WAV — чтобы проверить, что расшифровка сохраняется. В обычной работе папка не нужна.', 'en': 'Android/data/com.dictapro.app/files\n\nTexts and temporary WAVs are stored here — to verify that transcription is saved. In normal use the folder is not needed.', 'de': 'Android/data/com.dictapro.app/files\n\nHier liegen Texte und temporäre WAVs — um zu prüfen, dass die Transkription gespeichert wird. Im normalen Betrieb ist der Ordner nicht nötig.',
      'fr': 'Android/data/com.dictapro.app/files\n\nLes textes et les WAV temporaires se trouvent ici — pour vérifier que la transcription est bien enregistrée. En usage normal, ce dossier est inutile.', 'es': 'Android/data/com.dictapro.app/files\n\nAquí están los textos y los WAV temporales — para comprobar que la transcripción se guarda. En el uso normal la carpeta no hace falta.', 'it': 'Android/data/com.dictapro.app/files\n\nQui ci sono testi e WAV temporanei — per verificare che la trascrizione venga salvata. Nell\'uso normale la cartella non serve.',
    },
    'got_it': {
      'ru': 'Понятно', 'en': 'Got it', 'de': 'Verstanden',
      'fr': 'Compris', 'es': 'Entendido', 'it': 'Capito',
    },
    'splash_tagline': {
      'ru': 'Голос → Текст', 'en': 'Voice → Text', 'de': 'Stimme → Text',
      'fr': 'Voix → Texte', 'es': 'Voz → Texto', 'it': 'Voce → Testo',
    },
    'splash_footer': {
      'ru': 'модель внутри · интернет не нужен', 'en': 'model inside · no internet needed', 'de': 'Modell integriert · kein Internet nötig',
      'fr': 'modèle intégré · sans internet', 'es': 'modelo integrado · sin internet', 'it': 'modello integrato · senza internet',
    },
    'ui_lang_title': {
      'ru': 'Язык приложения', 'en': 'App language', 'de': 'App-Sprache',
      'fr': 'Langue de l\'application', 'es': 'Idioma de la aplicación', 'it': 'Lingua dell\'app',
    },
    'ui_lang_system': {
      'ru': 'Системный (как в телефоне)', 'en': 'System (like on the phone)', 'de': 'System (wie am Handy)',
      'fr': 'Système (comme le téléphone)', 'es': 'Sistema (como el teléfono)', 'it': 'Sistema (come sul telefono)',
    },
    'asr_lang_title': {
      'ru': 'Язык расшифровки', 'en': 'Transcription language', 'de': 'Transkriptionssprache',
      'fr': 'Langue de transcription', 'es': 'Idioma de transcripción', 'it': 'Lingua di trascrizione',
    },
    'asr_lang_saved': {
      'ru': 'Язык расшифровки сохранён', 'en': 'Transcription language saved', 'de': 'Transkriptionssprache gespeichert',
      'fr': 'Langue de transcription enregistrée', 'es': 'Idioma de transcripción guardado', 'it': 'Lingua di trascrizione salvata',
    },
    'asr_gigaam_offline': {
      'ru': 'офлайн-модель GigaAM', 'en': 'GigaAM offline model', 'de': 'GigaAM-Offline-Modell',
      'fr': 'modèle GigaAM hors ligne', 'es': 'modelo GigaAM sin conexión', 'it': 'modello GigaAM offline',
    },
    'asr_whisper_offline': {
      'ru': 'Whisper, офлайн', 'en': 'Whisper, offline', 'de': 'Whisper, offline',
      'fr': 'Whisper, hors ligne', 'es': 'Whisper, sin conexión', 'it': 'Whisper, offline',
    },
    'unit_hz': {
      'ru': 'Гц', 'en': 'Hz', 'de': 'Hz',
      'fr': 'Hz', 'es': 'Hz', 'it': 'Hz',
    },
    'filter_all': {
      'ru': 'Все', 'en': 'All', 'de': 'Alle',
      'fr': 'Tous', 'es': 'Todos', 'it': 'Tutti',
    },
    'filter_today': {
      'ru': 'Сегодня', 'en': 'Today', 'de': 'Heute',
      'fr': 'Aujourd\'hui', 'es': 'Hoy', 'it': 'Oggi',
    },
    'filter_queued': {
      'ru': 'В очереди', 'en': 'In queue', 'de': 'In Warteschlange',
      'fr': 'En attente', 'es': 'En cola', 'it': 'In coda',
    },
    'texts_subtitle': {
      'ru': 'расшифровки записей', 'en': 'recording transcripts', 'de': 'Aufnahme-Transkripte',
      'fr': 'transcriptions des enregistrements', 'es': 'transcripciones de grabaciones', 'it': 'trascrizioni delle registrazioni',
    },
    'summaries_subtitle': {
      'ru': 'конспекты', 'en': 'digests', 'de': 'Konspekte',
      'fr': 'synthèses', 'es': 'resúmenes', 'it': 'sintesi',
    },
    'empty_no_transcripts_title': {
      'ru': 'Пока нет расшифрованных записей', 'en': 'No transcribed recordings yet', 'de': 'Noch keine transkribierten Aufnahmen',
      'fr': 'Aucun enregistrement transcrit', 'es': 'Aún no hay grabaciones transcritas', 'it': 'Ancora nessuna registrazione trascritta',
    },
    'empty_no_transcripts_body': {
      'ru': 'Расшифруйте любую запись — и она появится здесь.', 'en': 'Transcribe any recording — and it will appear here.', 'de': 'Transkribieren Sie eine Aufnahme — und sie erscheint hier.',
      'fr': 'Transcrivez un enregistrement — il apparaîtra ici.', 'es': 'Transcribe cualquier grabación — y aparecerá aquí.', 'it': 'Trascrivi una registrazione — e apparirà qui.',
    },
    'empty_no_summaries_title': {
      'ru': 'Пока нет конспектов', 'en': 'No digests yet', 'de': 'Noch keine Konspekte',
      'fr': 'Aucune synthèse pour l\'instant', 'es': 'Aún no hay resúmenes', 'it': 'Ancora nessuna sintesi',
    },
    'empty_no_summaries_body': {
      'ru': 'Соберите «Итоги» на карточке записи — и они появятся здесь.', 'en': 'Generate "Summaries" on a recording card — and they will appear here.', 'de': 'Erstellen Sie „Zusammenfassungen“ auf der Aufnahmekarte — und sie erscheinen hier.',
      'fr': 'Générez les « Résumés » sur la fiche d\'un enregistrement — ils apparaîtront ici.', 'es': 'Genera «Resúmenes» en la tarjeta de una grabación — y aparecerán aquí.', 'it': 'Genera i «Riepiloghi» dalla scheda di una registrazione — e appariranno qui.',
    },
    'asr_dialog_title': {
      'ru': 'На каком языке расшифровать?', 'en': 'Which language should be transcribed?', 'de': 'In welcher Sprache transkribieren?',
      'fr': 'Dans quelle langue transcrire ?', 'es': '¿En qué idioma transcribir?', 'it': 'In quale lingua trascrivere?',
    },
    'asr_dont_ask': {
      'ru': 'Больше не спрашивать', 'en': 'Don\'t ask again', 'de': 'Nicht mehr fragen',
      'fr': 'Ne plus demander', 'es': 'No volver a preguntar', 'it': 'Non chiedere più',
    },
    'model_prep_progress': {
      'ru': '{c} из {t} МБ · {p}%', 'en': '{c} of {t} MB · {p}%', 'de': '{c} von {t} MB · {p}%',
      'fr': '{c} sur {t} Mo · {p}%', 'es': '{c} de {t} MB · {p}%', 'it': '{c} di {t} MB · {p}%',
    },
    'rec_empty_file_msg': {
      'ru': 'Файл записи пустой (0 байт) — расшифровывать нечего. Похоже, запись оборвалась в самом начале.', 'en': 'The recording file is empty (0 bytes) — nothing to transcribe. It looks like the recording stopped right at the start.', 'de': 'Die Aufnahmedatei ist leer (0 Bytes) — nichts zu transkribieren. Die Aufnahme wurde wohl ganz am Anfang abgebrochen.',
      'fr': 'Le fichier d\'enregistrement est vide (0 octet) — rien à transcrire. L\'enregistrement s\'est probablement coupé au tout début.', 'es': 'El archivo de grabación está vacío (0 bytes) — no hay nada que transcribir. La grabación se cortó justo al principio.', 'it': 'Il file di registrazione è vuoto (0 byte) — niente da trascrivere. La registrazione si è interrotta subito all\'inizio.',
    },
    'rec_decode_failed_msg': {
      'ru': 'Не удалось прочитать звук: файл пуст или повреждён. Запишите заново или импортируйте другой файл.', 'en': 'Could not read the audio: the file is empty or damaged. Record again or import another file.', 'de': 'Audio konnte nicht gelesen werden: Datei leer oder beschädigt. Nehmen Sie neu auf oder importieren Sie eine andere Datei.',
      'fr': 'Impossible de lire l\'audio : fichier vide ou endommagé. Réenregistrez ou importez un autre fichier.', 'es': 'No se pudo leer el audio: el archivo está vacío o dañado. Vuelve a grabar o importa otro archivo.', 'it': 'Impossibile leggere l\'audio: file vuoto o danneggiato. Registra di nuovo o importa un altro file.',
    },
    'rec_no_speech_msg': {
      'ru': 'В записи не найдена речь: возможно, начало пустое или звук слишком тихий. Проверьте запись и попробуйте снова.', 'en': 'No speech found in the recording: perhaps the start is empty or the sound is too quiet. Check the recording and try again.', 'de': 'In der Aufnahme wurde keine Sprache gefunden: Vielleicht ist der Anfang leer oder der Ton zu leise. Prüfen Sie die Aufnahme und versuchen Sie es erneut.',
      'fr': 'Aucune parole détectée dans l\'enregistrement : le début est peut-être vide ou le son trop faible. Vérifiez l\'enregistrement et réessayez.', 'es': 'No se encontró voz en la grabación: puede que el inicio esté vacío o el sonido sea demasiado bajo. Revisa la grabación e inténtalo de nuevo.', 'it': 'Nessuna voce trovata nella registrazione: forse l\'inizio è vuoto o l\'audio è troppo basso. Controlla la registrazione e riprova.',
    },
    'audio_lost_banner': {
      'ru': 'Аудио этой записи не найдено — файл был потерян старой версией приложения (исправлено с 29.09). Новые записи сохраняются.', 'en': 'The audio for this recording was not found — the file was lost by an old app version (fixed since 29.09). New recordings are kept.', 'de': 'Das Audio dieser Aufnahme fehlt — die Datei ging in einer alten App-Version verloren (behoben seit 29.09). Neue Aufnahmen bleiben erhalten.',
      'fr': 'L\'audio de cet enregistrement est introuvable — le fichier a été perdu par une ancienne version de l\'application (corrigé depuis le 29.09). Les nouveaux enregistrements sont conservés.', 'es': 'No se encontró el audio de esta grabación — el archivo se perdió con una versión antigua de la aplicación (corregido desde el 29.09). Las grabaciones nuevas se conservan.', 'it': 'L\'audio di questa registrazione non è stato trovato — il file è andato perso con una vecchia versione dell\'app (corretto dal 29.09). Le nuove registrazioni vengono conservate.',
    },
    'import_tooltip': {
      'ru': 'Импорт', 'en': 'Import', 'de': 'Importieren',
      'fr': 'Importer', 'es': 'Importar', 'it': 'Importa',
    },
    'favorites_tooltip': {
      'ru': 'Избранное', 'en': 'Favorites', 'de': 'Favoriten',
      'fr': 'Favoris', 'es': 'Favoritos', 'it': 'Preferiti',
    },
    'audio_lost_snack': {
      'ru': 'Аудио этой записи не найдено — файл потерян старой версией (исправлено 29.09)', 'en': 'The audio for this recording was not found — the file was lost by an old version (fixed 29.09)', 'de': 'Das Audio dieser Aufnahme fehlt — die Datei ging in einer alten Version verloren (behoben am 29.09)',
      'fr': 'L\'audio de cet enregistrement est introuvable — fichier perdu par une ancienne version (corrigé le 29.09)', 'es': 'No se encontró el audio de esta grabación — el archivo se perdió con una versión antigua (corregido el 29.09)', 'it': 'L\'audio di questa registrazione non è stato trovato — file perso da una vecchia versione (corretto il 29.09)',
    },
    'player_speed': {
      'ru': 'Скорость', 'en': 'Speed', 'de': 'Geschwindigkeit',
      'fr': 'Vitesse', 'es': 'Velocidad', 'it': 'Velocità',
    },
    'sub_year_badge': {
      'ru': 'выгоднее до 25%', 'en': 'up to 25% off', 'de': 'bis zu 25 % günstiger',
      'fr': 'jusqu\'à 25 % d\'économie', 'es': 'hasta un 25 % de descuento', 'it': 'fino al 25% in meno',
    },
    'sub_hours_per_month': {
      'ru': 'ИИ-часы: {h} ч в месяц', 'en': 'AI hours: {h} h per month', 'de': 'KI-Stunden: {h} h pro Monat',
      'fr': 'Heures IA : {h} h par mois', 'es': 'Horas de IA: {h} h al mes', 'it': 'Ore AI: {h} h al mese',
    },
    'sub_best_price_year': {
      'ru': 'ЛУЧШАЯ ЦЕНА ЗА ГОД', 'en': 'BEST PRICE PER YEAR', 'de': 'BESTPREIS PRO JAHR',
      'fr': 'MEILLEUR PRIX DE L\'ANNÉE', 'es': 'MEJOR PRECIO DEL AÑO', 'it': 'MIGLIOR PREZZO DELL\'ANNO',
    },
    'sub_hours_short': {
      'ru': '{n} ч', 'en': '{n} h', 'de': '{n} h',
      'fr': '{n} h', 'es': '{n} h', 'it': '{n} h',
    },
    'summary_prep_text': {
      'ru': 'Готовим текст…', 'en': 'Preparing text…', 'de': 'Text wird vorbereitet…',
      'fr': 'Préparation du texte…', 'es': 'Preparando el texto…', 'it': 'Preparazione del testo…',
    },
    'export_btn': {
      'ru': 'Экспорт', 'en': 'Export', 'de': 'Export',
      'fr': 'Export', 'es': 'Exportar', 'it': 'Esporta',
    },
    'export_title': {
      'ru': 'ДиктаПро — Транскрипция', 'en': 'DictaPro — Transcript', 'de': 'DictaPro — Transkription',
      'fr': 'DictaPro — Transcription', 'es': 'DictaPro — Transcripción', 'it': 'DictaPro — Trascrizione',
    },
    'export_label_date': {
      'ru': 'Дата: {v}', 'en': 'Date: {v}', 'de': 'Datum: {v}',
      'fr': 'Date : {v}', 'es': 'Fecha: {v}', 'it': 'Data: {v}',
    },
    'export_label_duration': {
      'ru': 'Длительность: {v}', 'en': 'Duration: {v}', 'de': 'Dauer: {v}',
      'fr': 'Durée : {v}', 'es': 'Duración: {v}', 'it': 'Durata: {v}',
    },
    'export_label_duration_sec': {
      'ru': 'Длительность: {v} сек', 'en': 'Duration: {v} sec', 'de': 'Dauer: {v} Sek.',
      'fr': 'Durée : {v} s', 'es': 'Duración: {v} s', 'it': 'Durata: {v} s',
    },
    'export_full_text_sep': {
      'ru': '--- Полный текст ---', 'en': '--- Full text ---', 'de': '--- Volltext ---',
      'fr': '--- Texte complet ---', 'es': '--- Texto completo ---', 'it': '--- Testo completo ---',
    },
    'export_html_header': {
      'ru': 'ДиктаПро | {d} | {s} сек', 'en': 'DictaPro | {d} | {s} sec', 'de': 'DictaPro | {d} | {s} Sek.',
      'fr': 'DictaPro | {d} | {s} s', 'es': 'DictaPro | {d} | {s} s', 'it': 'DictaPro | {d} | {s} s',
    },
    'export_speaker_label': {
      'ru': 'Говорящий {s}', 'en': 'Speaker {s}', 'de': 'Sprecher {s}',
      'fr': 'Locuteur {s}', 'es': 'Hablante {s}', 'it': 'Parlante {s}',
    },
    'no_text': {
      'ru': 'Нет текста', 'en': 'No text', 'de': 'Kein Text',
      'fr': 'Pas de texte', 'es': 'Sin texto', 'it': 'Nessun testo',
    },
    'share_subject_transcript': {
      'ru': 'Транскрипция записи', 'en': 'Recording transcript', 'de': 'Aufnahme-Transkript',
      'fr': 'Transcription de l\'enregistrement', 'es': 'Transcripción de la grabación', 'it': 'Trascrizione della registrazione',
    },
    'share_audio_caption': {
      'ru': 'Аудиозапись из ДиктаПро', 'en': 'Audio recording from DictaPro', 'de': 'Audioaufnahme aus DictaPro',
      'fr': 'Enregistrement audio de DictaPro', 'es': 'Grabación de audio de DictaPro', 'it': 'Registrazione audio da DictaPro',
    },
    'default_title_recording': {
      'ru': 'Запись {d}, {t}', 'en': 'Recording {d}, {t}', 'de': 'Aufnahme {d}, {t}',
      'fr': 'Enregistrement {d}, {t}', 'es': 'Grabación {d}, {t}', 'it': 'Registrazione {d}, {t}',
    },
    'notif_recording_title': {
      'ru': 'DictaPro — идёт запись', 'en': 'DictaPro — recording', 'de': 'DictaPro — Aufnahme läuft',
      'fr': 'DictaPro — enregistrement en cours', 'es': 'DictaPro — grabando', 'it': 'DictaPro — registrazione in corso',
    },
    'notif_recording_text': {
      'ru': 'Запись продолжается при выключенном экране', 'en': 'Recording continues with the screen off', 'de': 'Die Aufnahme läuft auch bei ausgeschaltetem Bildschirm weiter',
      'fr': 'L\'enregistrement continue écran éteint', 'es': 'La grabación continúa con la pantalla apagada', 'it': 'La registrazione continua a schermo spento',
    },
    'notif_channel_transcription': {
      'ru': 'Расшифровка', 'en': 'Transcription', 'de': 'Transkription',
      'fr': 'Transcription', 'es': 'Transcripción', 'it': 'Trascrizione',
    },
    'notif_transcription_done': {
      'ru': 'Расшифровка готова', 'en': 'Transcription ready', 'de': 'Transkription fertig',
      'fr': 'Transcription terminée', 'es': 'Transcripción lista', 'it': 'Trascrizione pronta',
    },
    'notif_transcription_saved': {
      'ru': 'Текст сохранён в записи', 'en': 'Text saved to the recording', 'de': 'Text in der Aufnahme gespeichert',
      'fr': 'Texte enregistré dans l\'enregistrement', 'es': 'Texto guardado en la grabación', 'it': 'Testo salvato nella registrazione',
    },
    'keepalive_title': {
      'ru': 'DictaPro — идёт расшифровка', 'en': 'DictaPro — transcribing', 'de': 'DictaPro — Transkription läuft',
      'fr': 'DictaPro — transcription en cours', 'es': 'DictaPro — transcribiendo', 'it': 'DictaPro — trascrizione in corso',
    },
    'notif_channel_recording': {
      'ru': 'Запись DictaPro', 'en': 'DictaPro recording', 'de': 'DictaPro-Aufnahme',
      'fr': 'Enregistrement DictaPro', 'es': 'Grabación DictaPro', 'it': 'Registrazione DictaPro',
    },
    'untitled': {
      'ru': 'Без названия', 'en': 'Untitled', 'de': 'Ohne Titel',
      'fr': 'Sans titre', 'es': 'Sin título', 'it': 'Senza titolo',
    },
    'elapsed_seconds': {
      'ru': 'прошло {n} с', 'en': 'elapsed {n} s', 'de': '{n} s vergangen',
      'fr': 'écoulé : {n} s', 'es': 'transcurrido {n} s', 'it': 'trascorso {n} s',
    },
    'sum_type': {
      'ru': 'Тип: {v}', 'en': 'Type: {v}', 'de': 'Typ: {v}',
      'fr': 'Type : {v}', 'es': 'Tipo: {v}', 'it': 'Tipo: {v}',
    },
    'sum_dates': {
      'ru': 'Даты: {v}', 'en': 'Dates: {v}', 'de': 'Daten: {v}',
      'fr': 'Dates : {v}', 'es': 'Fechas: {v}', 'it': 'Date: {v}',
    },
    'sum_amounts': {
      'ru': 'Суммы: {v}', 'en': 'Amounts: {v}', 'de': 'Beträge: {v}',
      'fr': 'Montants : {v}', 'es': 'Importes: {v}', 'it': 'Importi: {v}',
    },
    'sum_contacts': {
      'ru': 'Контакты: {v}', 'en': 'Contacts: {v}', 'de': 'Kontakte: {v}',
      'fr': 'Contacts : {v}', 'es': 'Contactos: {v}', 'it': 'Contatti: {v}',
    },
    'sum_key_points': {
      'ru': 'Ключевые моменты:', 'en': 'Key points:', 'de': 'Kernpunkte:',
      'fr': 'Points clés :', 'es': 'Puntos clave:', 'it': 'Punti chiave:',
    },
    'sum_actions': {
      'ru': 'Действия:', 'en': 'Actions:', 'de': 'Aktionen:',
      'fr': 'Actions :', 'es': 'Acciones:', 'it': 'Azioni:',
    },
    'stt_bad_wav': {
      'ru': 'Не удалось прочитать WAV-заголовок', 'en': 'Could not read the WAV header', 'de': 'WAV-Header konnte nicht gelesen werden',
      'fr': 'Impossible de lire l\'en-tête WAV', 'es': 'No se pudo leer el encabezado WAV', 'it': 'Impossibile leggere l\'intestazione WAV',
    },
    'ai_hours_left': {
      'ru': 'ИИ-часы: осталось {h} ч', 'en': 'AI hours left: {h} h', 'de': 'KI-Stunden übrig: {h} h',
      'fr': 'Heures IA restantes : {h} h', 'es': 'Horas de IA restantes: {h} h', 'it': 'Ore AI rimaste: {h} h',
    },
    'ai_hours_breakdown': {
      'ru': ' (по подписке {a}, пакеты {p})', 'en': ' ({a} plan, {p} packs)', 'de': ' (Abo {a}, Pakete {p})',
      'fr': ' ({a} abonnement, {p} packs)', 'es': ' ({a} plan, {p} packs)', 'it': ' ({a} abbonamento, {p} pack)',
    },
    'usage_used_of': {
      'ru': '{u} из {n}', 'en': '{u} of {n}', 'de': '{u} von {n}',
      'fr': '{u} sur {n}', 'es': '{u} de {n}', 'it': '{u} di {n}',
    },
    'sum_t_audiobook': {
      'ru': 'Аудиокнига / Лекция', 'en': 'Audiobook / Lecture', 'de': 'Hörbuch / Vorlesung', 'fr': 'Livre audio / Cours', 'es': 'Audiolibro / Clase', 'it': 'Audiolibro / Lezione',
    },
    'sum_t_document': {
      'ru': 'Доклад / Документ', 'en': 'Report / Document', 'de': 'Vortrag / Dokument', 'fr': 'Rapport / Document', 'es': 'Informe / Documento', 'it': 'Rapporto / Documento',
    },
    'sum_t_lecture': {
      'ru': 'Лекция / Образование', 'en': 'Lecture / Education', 'de': 'Vorlesung / Bildung', 'fr': 'Cours / Éducation', 'es': 'Clase / Educación', 'it': 'Lezione / Istruzione',
    },
    'sum_t_business': {
      'ru': 'Бизнес-встреча', 'en': 'Business meeting', 'de': 'Geschäftstreffen', 'fr': 'Réunion d\'affaires', 'es': 'Reunión de negocios', 'it': 'Riunione di lavoro',
    },
    'sum_t_interview': {
      'ru': 'Интервью', 'en': 'Interview', 'de': 'Interview', 'fr': 'Entretien', 'es': 'Entrevista', 'it': 'Intervista',
    },
    'sum_t_notes': {
      'ru': 'Заметки', 'en': 'Notes', 'de': 'Notizen', 'fr': 'Notes', 'es': 'Notas', 'it': 'Note',
    },
    'diag_file_header': {
      'ru': '=== ДиктаПро: диагностика прогона ===', 'en': '=== DictaPro: run diagnostics ===', 'de': '=== DictaPro: Diagnose des Durchlaufs ===', 'fr': '=== DictaPro : diagnostic d\'exécution ===', 'es': '=== DictaPro: diagnóstico de la ejecución ===', 'it': '=== DictaPro: diagnostica esecuzione ===',
    },
    'diag_file_source': {
      'ru': 'источник: {v}', 'en': 'source: {v}', 'de': 'Quelle: {v}', 'fr': 'source : {v}', 'es': 'origen: {v}', 'it': 'origine: {v}',
    },
    'diag_file_counts': {
      'ru': 'символов: {c}; слов: {w}', 'en': 'characters: {c}; words: {w}', 'de': 'Zeichen: {c}; Wörter: {w}', 'fr': 'caractères : {c} ; mots : {w}', 'es': 'caracteres: {c}; palabras: {w}', 'it': 'caratteri: {c}; parole: {w}',
    },
    'diag_file_time': {
      'ru': 'время: {v} с', 'en': 'time: {v} s', 'de': 'Zeit: {v} s', 'fr': 'durée : {v} s', 'es': 'tiempo: {v} s', 'it': 'tempo: {v} s',
    },
    'diag_file_text_sep': {
      'ru': '=== ТЕКСТ ===', 'en': '=== TEXT ===', 'de': '=== TEXT ===', 'fr': '=== TEXTE ===', 'es': '=== TEXTO ===', 'it': '=== TESTO ===',
    },

    'sum_title_business': {
      'ru': 'Результаты встречи', 'en': 'Meeting results', 'de': 'Besprechungsergebnisse',
      'fr': 'Résultats de la réunion', 'es': 'Resultados de la reunión', 'it': 'Esiti della riunione',
    },
    'sum_title_lecture': {
      'ru': 'Конспект лекции', 'en': 'Lecture notes', 'de': 'Vorlesungsnotizen',
      'fr': 'Notes de cours', 'es': 'Apuntes de clase', 'it': 'Appunti della lezione',
    },
    'sum_title_personal': {
      'ru': 'Личные заметки', 'en': 'Personal notes', 'de': 'Persönliche Notizen',
      'fr': 'Notes personnelles', 'es': 'Notas personales', 'it': 'Note personali',
    },
    'sum_title_general': {
      'ru': 'Саммари', 'en': 'Summary', 'de': 'Zusammenfassung',
      'fr': 'Résumé', 'es': 'Resumen', 'it': 'Riassunto',
    },
    'sum_title_no_data': {
      'ru': 'Нет данных', 'en': 'No data', 'de': 'Keine Daten',
      'fr': 'Aucune donnée', 'es': 'Sin datos', 'it': 'Nessun dato',
    },
    'sum_text_too_short': {
      'ru': 'Текст слишком короткий для саммари', 'en': 'Text is too short for a summary', 'de': 'Text zu kurz für eine Zusammenfassung',
      'fr': 'Texte trop court pour un résumé', 'es': 'Texto demasiado corto para un resumen', 'it': 'Testo troppo breve per un riassunto',
    },
    'sum_t_narrative': {
      'ru': 'История / Рассказ', 'en': 'Story / Narrative', 'de': 'Geschichte / Erzählung',
      'fr': 'Histoire / Récit', 'es': 'Historia / Relato', 'it': 'Storia / Racconto',
    },
    'sum_t_general': {
      'ru': 'Общая запись', 'en': 'General recording', 'de': 'Allgemeine Aufnahme',
      'fr': 'Enregistrement général', 'es': 'Grabación general', 'it': 'Registrazione generica',
    },
    'sum_sec_topics': {
      'ru': 'Темы:', 'en': 'Topics:', 'de': 'Themen:',
      'fr': 'Sujets :', 'es': 'Temas:', 'it': 'Argomenti:',
    },
    'sum_sec_decisions': {
      'ru': 'Решения:', 'en': 'Decisions:', 'de': 'Beschlüsse:',
      'fr': 'Décisions :', 'es': 'Decisiones:', 'it': 'Decisioni:',
    },
    'sum_sec_finance': {
      'ru': 'Финансы:', 'en': 'Finance:', 'de': 'Finanzen:',
      'fr': 'Finances :', 'es': 'Finanzas:', 'it': 'Finanze:',
    },
    'sum_sec_deadlines': {
      'ru': 'Сроки:', 'en': 'Deadlines:', 'de': 'Fristen:',
      'fr': 'Échéances :', 'es': 'Plazos:', 'it': 'Scadenze:',
    },
    'sum_sec_contacts': {
      'ru': 'Контакты:', 'en': 'Contacts:', 'de': 'Kontakte:',
      'fr': 'Contacts :', 'es': 'Contactos:', 'it': 'Contatti:',
    },
    'sum_sec_actions': {
      'ru': 'Что делать:', 'en': 'To do:', 'de': 'To-dos:',
      'fr': 'À faire :', 'es': 'Por hacer:', 'it': 'Da fare:',
    },
    'sum_sec_key_points': {
      'ru': 'Ключевые мысли:', 'en': 'Key points:', 'de': 'Kernpunkte:',
      'fr': 'Points clés :', 'es': 'Puntos clave:', 'it': 'Punti chiave:',
    },
    'sum_sec_definitions': {
      'ru': 'Определения:', 'en': 'Definitions:', 'de': 'Definitionen:',
      'fr': 'Définitions :', 'es': 'Definiciones:', 'it': 'Definizioni:',
    },
    'sum_sec_concepts': {
      'ru': 'Ключевые понятия:', 'en': 'Key concepts:', 'de': 'Schlüsselbegriffe:',
      'fr': 'Concepts clés :', 'es': 'Conceptos clave:', 'it': 'Concetti chiave:',
    },
    'sum_sec_main_points': {
      'ru': 'Основные тезисы:', 'en': 'Main points:', 'de': 'Kernthesen:',
      'fr': 'Points principaux :', 'es': 'Puntos principales:', 'it': 'Punti principali:',
    },
    'sum_sec_questions': {
      'ru': 'Вопросы:', 'en': 'Questions:', 'de': 'Fragen:',
      'fr': 'Questions :', 'es': 'Preguntas:', 'it': 'Domande:',
    },
    'sum_sec_insights': {
      'ru': 'Инсайты:', 'en': 'Insights:', 'de': 'Erkenntnisse:',
      'fr': 'Aperçus :', 'es': 'Ideas clave:', 'it': 'Approfondimenti:',
    },
    'sum_sec_quotes': {
      'ru': 'Цитаты:', 'en': 'Quotes:', 'de': 'Zitate:',
      'fr': 'Citations :', 'es': 'Citas:', 'it': 'Citazioni:',
    },
    'sum_sec_briefly': {
      'ru': 'Кратко:', 'en': 'Briefly:', 'de': 'Kurz:',
      'fr': 'En bref :', 'es': 'En breve:', 'it': 'In breve:',
    },
    'sum_sec_ideas': {
      'ru': 'Идеи:', 'en': 'Ideas:', 'de': 'Ideen:',
      'fr': 'Idées :', 'es': 'Ideas:', 'it': 'Idee:',
    },
    'sum_sec_tasks': {
      'ru': 'Задачи:', 'en': 'Tasks:', 'de': 'Aufgaben:',
      'fr': 'Tâches :', 'es': 'Tareas:', 'it': 'Attività:',
    },
    'sum_sec_dates': {
      'ru': 'Даты:', 'en': 'Dates:', 'de': 'Daten:',
      'fr': 'Dates :', 'es': 'Fechas:', 'it': 'Date:',
    },
    'sum_sec_notes': {
      'ru': 'Заметки:', 'en': 'Notes:', 'de': 'Notizen:',
      'fr': 'Notes :', 'es': 'Notas:', 'it': 'Note:',
    },

  };

  static String _langCode(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    return _dict.values.first.containsKey(lang) ? lang : 'ru';
  }

  static String _t(String key, BuildContext context) =>
      _dict[key]?[_langCode(context)] ?? _dict[key]?['ru'] ?? key;

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

  /// ---------- Task 068-1: доступ к строкам без BuildContext ----------
  /// Язык берём из настроек UI ('ui_lang'), иначе — язык системы
  /// (PlatformDispatcher), иначе русский.
  static String? _isolateLang;

  /// Зафиксировать язык для фонового compute-изолята: там настройки
  /// UI недоступны, и язык мог бы определиться как системный.
  static void pinIsolateLang(String? code) => _isolateLang = code;

  static String _globalLangCode() {
    final iso = _isolateLang;
    if (iso != null) return iso;
    String? code;
    final pinned = LocaleController.instance.locale.value;
    if (pinned != null) {
      code = pinned.languageCode;
    } else {
      try {
        final box = Hive.box<dynamic>('settings');
        final v = box.get('ui_lang')?.toString();
        if (v != null && v.isNotEmpty && v != 'system') code = v;
      } catch (_) {}
    }
    code ??= PlatformDispatcher.instance.locale.languageCode;
    return _dict.values.first.containsKey(code) ? code : 'ru';
  }

  /// Публичный доступ к текущему языку UI (для DateFormat и т.п.).
  static String globalLangCode() => _globalLangCode();

  /// Как [t], но для мест без BuildContext (уведомления, сервисы, экспорт).
  static String tGlobal(String key) =>
      _dict[key]?[_globalLangCode()] ?? _dict[key]?['ru'] ?? key;

  /// Как [tf], но без BuildContext.
  static String tfGlobal(String key, Map<String, String> params) =>
      _fmt(tGlobal(key), params);

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
  static String humanDuration(int ms, {String lang = 'ru'}) {
    final totalMin = ms ~/ 60000;
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    final ch = lang == 'ru' ? 'ч' : 'h';
    final cm = switch (lang) {
      'ru' => 'мин',
      'de' => 'Min',
      _ => 'min',
    };
    if (h > 0 && m > 0) return '$h $ch $m $cm';
    if (h > 0) return '$h $ch';
    return '$m $cm';
  }

  /// Оценка времени расшифровки: «≈ 3 ч», «≈ 45 мин».
  /// Замерено на устройстве (task 053): N минут расшифровки на 1 час аудио.
  /// Коэффициент — из замера Claude (см. журнал), консервативный запас ×1.2.
  static const _kTranscribeMinutesPerAudioHour = 20.0; // PLACEHOLDER до замера

  static String transcribeEstimate(int audioMs, {String lang = 'ru'}) {
    final audioHours = audioMs / 3600000.0;
    final estMin = (audioHours * _kTranscribeMinutesPerAudioHour * 1.2).round();
    final h = estMin ~/ 60;
    final m = estMin % 60;
    final ch = lang == 'ru' ? 'ч' : 'h';
    final cm = switch (lang) {
      'ru' => 'мин',
      'de' => 'Min',
      _ => 'min',
    };
    if (h > 0 && m > 0) return '≈ $h $ch $m $cm';
    if (h > 0) return '≈ $h $ch';
    return '≈ $m $cm';
  }
}
