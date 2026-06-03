class SummaryService {
  static String generateSummary(String text) {
    String type = _detectType(text);
    List<String> dates = _extractDates(text);
    List<String> amounts = _extractAmounts(text);
    List<String> phones = _extractPhones(text);
    List<String> actionItems = _extractActions(text);
    List<String> sentences = text.split('.').map((s) => s.trim()).where((s) => s.length > 10).toList();

    StringBuffer summary = StringBuffer();
    summary.writeln('Тип: $type');
    summary.writeln();

    if (dates.isNotEmpty) summary.writeln('Даты: ${dates.join(', ')}');
    if (amounts.isNotEmpty) summary.writeln('Суммы: ${amounts.join(', ')}');
    if (phones.isNotEmpty) summary.writeln('Контакты: ${phones.join(', ')}');

    summary.writeln();
    summary.writeln('Ключевые моменты:');
    List<String> keyPoints = _extractKeyPoints(sentences, type);
    for (var point in keyPoints.take(5)) {
      summary.writeln('• $point');
    }

    if (actionItems.isNotEmpty) {
      summary.writeln();
      summary.writeln('Действия:');
      for (var action in actionItems) {
        summary.writeln('• $action');
      }
    }

    return summary.toString();
  }

  static String _detectType(String text) {
    text = text.toLowerCase();
    int lectureScore = 0, businessScore = 0, interviewScore = 0, notesScore = 0, documentScore = 0, audiobookScore = 0;

    List<String> audiobookWords = ['глава', 'автор', 'читает', 'читатель', 'лекция', 'лекции', 'лектор', 'курс', 'курса', 'курсе', 'аудиокнига', 'аудиокниги', 'научпоп', 'нон-фикшн', 'биография', 'роман', 'повесть', 'рассказ', 'сборник', 'издание', 'издательство', 'перевод', 'переводчик', 'озвучил', 'озвучка', 'диктор', 'чтец', 'спикер', 'ведущий', 'ведущая', 'подкаст', 'подкасты', 'эпизод', 'серия', 'сезон', 'выпуск', 'выпуски'];
    for (var w in audiobookWords) if (text.contains(w)) audiobookScore += 4;

    List<String> documentWords = ['доклад', 'доклады', 'докладчик', 'статья', 'статьи', 'публикация', 'реферат', 'монография', 'диссертация', 'исследование', 'научный', 'академический', 'ораторское', 'выступление', 'презентация'];
    for (var w in documentWords) if (text.contains(w)) documentScore += 3;

    List<String> lectureWords = ['лекц', 'студент', 'занят', 'тема', 'экзамен', 'предмет', 'преподавател', 'аудитор', 'конспект', 'курс', 'учебник', 'семинар', 'практикум'];
    for (var w in lectureWords) if (text.contains(w)) lectureScore += 2;

    List<String> businessWords = ['встреч', 'договор', 'цена', 'сумма', 'заказ', 'клиент', 'сделк', 'оплат', 'контракт', 'согласов', 'переговор', 'совещание', 'заседание', 'конференц', 'деловой', 'бизнес', 'коммерческий', 'финансовый', 'бюджет', 'смета', 'поставщик', 'партнёр', 'инвестор', 'директор', 'менеджер', 'руководитель', 'компания', 'фирма', 'организация'];
    for (var w in businessWords) if (text.contains(w)) businessScore += 2;

    List<String> interviewWords = ['интервью', 'расскажите', 'как вы', 'почему', 'когда вы', 'опыт', 'работали', 'трудоустройство', 'собеседование', 'кандидат', 'резюме', 'вакансия', 'позиция', 'должность', 'hr', 'рекрутер', 'найм', 'подбор', 'персонал', 'кадры', 'зарплата', 'оклад'];
    for (var w in interviewWords) if (text.contains(w)) interviewScore += 2;

    List<String> notesWords = ['надо', 'нужно', 'купить', 'позвонить', 'сделать', 'встретиться', 'забрать', 'оплатить', 'идея', 'запомнить', 'не забыть', 'задача', 'список', 'дела', 'покупки', 'план', 'цели', 'мечта', 'желание', 'решение', 'выбор', 'итог', 'вывод', 'результат', 'рефлексия', 'размышления', 'мысли', 'впечатления', 'эмоции', 'чувства', 'настроение', 'день', 'вечер', 'утро', 'неделя', 'месяц', 'год', 'вчера', 'сегодня', 'завтра', 'ежедневник', 'дневник', 'запись', 'заметка', 'конспект', 'наброски', 'черновик', 'проект', 'задумка'];
    for (var w in notesWords) if (text.contains(w)) notesScore += 2;

    if (text.contains('лекц') || text.contains('студент') || text.contains('занят')) businessScore -= 5;
    if (text.contains('доклад') || text.contains('выступление') || text.contains('презентация')) { lectureScore -= 3; businessScore -= 5; }

    Map<String, int> scores = {
      'Аудиокнига / Лекция': audiobookScore,
      'Доклад / Документ': documentScore,
      'Лекция / Образование': lectureScore,
      'Бизнес-встреча': businessScore,
      'Интервью': interviewScore,
      'Заметки': notesScore,
    };

    String bestType = 'Заметки';
    int bestScore = 0;
    scores.forEach((type, score) {
      if (score > bestScore) { bestScore = score; bestType = type; }
    });
    return bestType;
  }

  static List<String> _extractKeyPoints(List<String> sentences, String type) {
    List<String> points = [];
    Map<String, List<String>> keywordsByType = {
      'Аудиокнига / Лекция': ['глава', 'автор', 'читает', 'лекция', 'лектор', 'курс', 'тема', 'темы', 'вопрос', 'вопросы', 'понятие', 'понятия', 'закон', 'законы', 'принцип', 'принципы', 'метод', 'методы', 'теория', 'теории', 'практика', 'практики', 'задача', 'задачи', 'решение', 'решения', 'результат', 'результаты', 'вывод', 'выводы', 'опыт', 'опыты', 'наблюдение', 'наблюдения', 'явление', 'явления', 'процесс', 'процессы', 'система', 'системы', 'структура', 'структуры', 'функция', 'функции', 'свойство', 'свойства', 'признак', 'признаки', 'причина', 'причины', 'следствие', 'следствия', 'цель', 'цели', 'значение', 'значения', 'смысл', 'смыслы', 'идея', 'идеи', 'мысль', 'мысли', 'знание', 'знания', 'информация', 'данные', 'факт', 'факты', 'доказательство', 'доказательства', 'аргумент', 'аргументы', 'пример', 'примеры', 'иллюстрация', 'иллюстрации', 'аналогия', 'аналогии', 'сравнение', 'сравнения', 'обобщение', 'обобщения', 'итог', 'итоги', 'суть', 'сущность', 'сущности', 'содержание', 'содержания', 'формулировка', 'формулировки', 'определение', 'определения', 'утверждение', 'утверждения', 'положение', 'положения', 'тезис', 'тезисы', 'обоснование', 'обоснования', 'пояснение', 'пояснения', 'комментарий', 'комментарии', 'примечание', 'примечания', 'дополнение', 'дополнения', 'уточнение', 'уточнения', 'поправка', 'поправки', 'исправление', 'исправления', 'доработка', 'доработки', 'пересмотр', 'пересмотры', 'корректировка', 'корректировки'],
      'Доклад / Документ': ['ясность', 'краткость', 'точность', 'структура', 'подбор слов', 'жаргон', 'аббревиатуры', 'стиль', 'доклад', 'доклады', 'докладчик', 'статья', 'статьи', 'публикация', 'реферат', 'монография', 'диссертация', 'исследование', 'научный', 'академический', 'ораторское', 'выступление', 'презентация'],
      'Лекция / Образование': ['лекция', 'лекции', 'лектор', 'студент', 'студенты', 'занятие', 'занятия', 'тема', 'темы', 'вопрос', 'вопросы', 'экзамен', 'экзамены', 'предмет', 'предметы', 'преподаватель', 'преподаватели', 'аудитория', 'конспект', 'план', 'курс', 'учебник', 'семинар', 'практикум'],
      'Бизнес-встреча': ['встреча', 'встречи', 'договор', 'цена', 'сумма', 'заказ', 'клиент', 'сделка', 'оплата', 'контракт', 'согласование', 'переговоры', 'совещание', 'заседание', 'решение', 'решения', 'итог', 'итоги', 'план', 'планы', 'задача', 'задачи', 'срок', 'сроки', 'дедлайн', 'бюджет', 'финансы'],
      'Интервью': ['интервью', 'вопрос', 'ответ', 'опыт', 'работа', 'должность', 'компания', 'зарплата', 'кандидат', 'резюме', 'вакансия', 'навыки', 'умения', 'квалификация'],
      'Заметки': ['идея', 'идеи', 'задача', 'задачи', 'план', 'планы', 'цель', 'цели', 'мечта', 'желание', 'решение', 'выбор', 'итог', 'вывод', 'результат', 'мысль', 'мысли', 'заметка', 'запись', 'напоминание'],
    };

    List<String> keywords = keywordsByType[type] ?? [];
    final personalPronouns = {'я', 'мы', 'ты', 'вы', 'он', 'она', 'оно', 'они', 'мне', 'тебе', 'ему', 'ей', 'нам', 'вам', 'им'};

    // Фильтруем: исключаем предложения с личными местоимениями
    List<String> filtered = [];
    for (var sentence in sentences) {
      String lower = sentence.toLowerCase();
      bool hasPersonal = false;
      for (var pronoun in personalPronouns) {
        if (lower.contains(' ' + pronoun + ' ') || lower.startsWith(pronoun + ' ')) {
          hasPersonal = true;
          break;
        }
      }
      if (!hasPersonal) filtered.add(sentence);
    }

    // Ищем предложения с ключевыми словами
    for (var sentence in filtered) {
      String lower = sentence.toLowerCase();
      for (var keyword in keywords) {
        if (lower.contains(keyword)) {
          if (sentence.length > 10 && sentence.length < 150) {
            points.add(sentence);
          }
          break;
        }
      }
    }

    points = points.toSet().toList();

    // Если мало — добавляем первое и последнее (из filtered)
    if (points.length < 3 && filtered.isNotEmpty) {
      if (filtered.first.length > 10) points.add(filtered.first);
      if (filtered.length > 1 && filtered.last.length > 10) points.add(filtered.last);
    }
    // Если совсем мало — берём из оригинальных (даже с местоимениями)
    if (points.length < 3 && sentences.isNotEmpty) {
      if (sentences.first.length > 10) points.add(sentences.first);
      if (sentences.length > 1 && sentences.last.length > 10) points.add(sentences.last);
    }

    return points.take(5).toList();
  }

  static List<String> _extractDates(String text) => [];
  static List<String> _extractAmounts(String text) => [];
  static List<String> _extractPhones(String text) => [];
  static List<String> _extractActions(String text) {
    List<String> actions = [];
    List<String> markers = ['надо', 'нужно', 'купить', 'позвонить', 'отправить', 'сделать'];
    List<String> sentences = text.split('.');
    for (var sentence in sentences) {
      for (var marker in markers) {
        if (sentence.toLowerCase().contains(marker)) {
          actions.add(sentence.trim());
          break;
        }
      }
    }
    return actions;
  }

  static List<String> getDecisions(String text) => _extractActions(text);
  static List<Map<String, dynamic>> getSpeakerStats(List<Map<String, dynamic>> segments) {
    final speakerMap = <String, List<String>>{};
    for (final seg in segments) {
      final speaker = seg['speaker'] as String? ?? '?';
      final text = seg['text'] as String? ?? '';
      speakerMap.putIfAbsent(speaker, () => []);
      speakerMap[speaker]!.add(text);
    }

    final stats = <Map<String, dynamic>>[];
    for (final entry in speakerMap.entries) {
      final allText = entry.value.join(' ');
      final wordCount = allText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      final words = allText.toLowerCase().split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)).where((w) => w.isNotEmpty).toList();
      final freq = <String, int>{};
      for (final w in words) { freq[w] = (freq[w] ?? 0) + 1; }
      final topWords = freq.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

      stats.add({
        'speaker': entry.key,
        'utteranceCount': entry.value.length,
        'wordCount': wordCount,
        'topWords': topWords.take(5).map((e) => '${e.key}(${e.value})').toList(),
      });
    }
    stats.sort((a, b) => (b['wordCount'] as int).compareTo(a['wordCount'] as int));
    return stats;
  }
}
