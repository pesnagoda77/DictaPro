import 'dart:math' as math;

/// Улучшенное саммари с контекстным анализом
/// Определяет тип текста и применяет соответствующий шаблон
/// Извлекает даты, суммы, контакты, экшн-айтемы
class EnhancedSummaryService {

  // ========== Определение типа текста ==========

  static TextType detectTextType(String text) {
    final lower = text.toLowerCase();

    // Бизнес-маркеры (высокий приоритет)
    final businessMarkers = [
      'решили', 'договорились', 'приняли решение', 'дедлайн', 'срок',
      'ответственный', 'задача', 'поручение', 'совещание', 'встреча',
      'обсудили', 'утвердили', 'согласовали', 'план', 'бюджет',
      'отчёт', 'презентация', 'клиент', 'заказчик', 'проект',
      'контракт', 'соглашение', 'оплата', 'цена', 'стоимость',
      'рублей', 'руб', 'тысяч', 'миллион', 'договор',
    ];

    // Лекция/образование
    final educationalMarkers = [
      'означает', 'представляет', 'является', 'состоит', 'включает',
      'например', 'то есть', 'другими словами', 'следовательно',
      'теория', 'метод', 'алгоритм', 'процесс', 'система',
      'функция', 'параметр', 'переменная', 'константа',
      'лекция', 'экзамен', 'тема', 'вопрос', 'ответ',
    ];

    // Интервью
    final interviewMarkers = [
      'интервью', 'вопрос', 'ответ', 'расскажите', 'почему',
      'как вы', 'что вы', 'какие', 'когда вы', 'где вы',
      'ваше мнение', 'ваш взгляд', 'ваш опыт', 'расскажите',
    ];

    // Личные заметки/идеи
    final personalMarkers = [
      'идея', 'заметка', 'нужно сделать', 'todo', 'задача',
      'придумал', 'подумал', 'вспомнил', 'важно', 'не забыть',
    ];

    int businessScore = businessMarkers.where((m) => lower.contains(m)).length;
    int educationalScore = educationalMarkers.where((m) => lower.contains(m)).length;
    int interviewScore = interviewMarkers.where((m) => lower.contains(m)).length;
    int personalScore = personalMarkers.where((m) => lower.contains(m)).length;

    final maxScore = [businessScore, educationalScore, interviewScore, personalScore]
        .reduce((a, b) => a > b ? a : b);

    if (maxScore == 0) return TextType.general;
    if (maxScore == businessScore) return TextType.business;
    if (maxScore == educationalScore) return TextType.educational;
    if (maxScore == interviewScore) return TextType.interview;
    if (maxScore == personalScore) return TextType.personal;

    return TextType.general;
  }

  // ========== Главный метод ==========

  static SummaryResult generateSummary(String text, {TextType? forcedType}) {
    final type = forcedType ?? detectTextType(text);
    final sentences = _splitIntoSentences(text);

    switch (type) {
      case TextType.business:
        return _summarizeBusiness(text, sentences);
      case TextType.educational:
        return _summarizeEducational(text, sentences);
      case TextType.interview:
        return _summarizeInterview(text, sentences);
      case TextType.personal:
        return _summarizePersonal(text, sentences);
      case TextType.general:
        return _summarizeGeneral(text, sentences);
      case TextType.narrative:
        return _summarizeGeneral(text, sentences); // fallback
    }
  }

  // ========== Бизнес-встреча ==========

  static SummaryResult _summarizeBusiness(String text, List<String> sentences) {
    final decisions = _extractDecisions(text);
    final deadlines = _extractDeadlines(text);
    final contacts = _extractContacts(text);
    final amounts = _extractAmounts(text);
    final actions = _extractActionItems(text);

    final points = <String>[];

    // Темы (топ-3 предложения с ключевыми словами)
    final topics = _extractTopics(sentences, 3);
    if (topics.isNotEmpty) {
      points.add('Темы:');
      for (final t in topics) {
        points.add('  • $t');
      }
    }

    // Решения
    if (decisions.isNotEmpty) {
      points.add('Решения:');
      for (final d in decisions.take(5)) {
        points.add('  • $d');
      }
    }

    // Суммы и цены
    if (amounts.isNotEmpty) {
      points.add('Финансы:');
      for (final a in amounts.take(3)) {
        points.add('  • $a');
      }
    }

    // Сроки
    if (deadlines.isNotEmpty) {
      points.add('Сроки:');
      for (final dl in deadlines.take(3)) {
        points.add('  • $dl');
      }
    }

    // Контакты
    if (contacts.isNotEmpty) {
      points.add('Контакты:');
      for (final c in contacts.take(3)) {
        points.add('  • $c');
      }
    }

    // Экшн-айтемы
    if (actions.isNotEmpty) {
      points.add('Что делать:');
      for (final a in actions.take(5)) {
        points.add('  □ $a');
      }
    }

    // Если ничего не нашли — выводим ключевые мысли
    if (points.isEmpty) {
      final keyPoints = _textRankSummary(sentences, 3);
      points.add('Ключевые мысли:');
      for (final p in keyPoints) {
        points.add('  • $p');
      }
    }

    return SummaryResult(
      title: 'Результаты встречи',
      type: TextType.business,
      points: points,
      fullText: text,
      actionItems: actions,
      contacts: contacts,
      deadlines: deadlines,
      amounts: amounts,
    );
  }

  // ========== Лекция / Образование ==========

  static SummaryResult _summarizeEducational(String text, List<String> sentences) {
    final definitions = _extractDefinitions(text);
    final keyConcepts = _extractKeyConcepts(text);
    final topics = _extractTopics(sentences, 5);

    final points = <String>[];

    if (topics.isNotEmpty) {
      points.add('Темы:');
      for (final t in topics) {
        points.add('  • $t');
      }
    }

    if (definitions.isNotEmpty) {
      points.add('Определения:');
      for (final d in definitions.take(3)) {
        points.add('  • $d');
      }
    }

    if (keyConcepts.isNotEmpty) {
      points.add('Ключевые понятия: ${keyConcepts.take(5).join(', ')}');
    }

    // Основные тезисы
    final mainPoints = _textRankSummary(sentences, 4);
    if (mainPoints.isNotEmpty) {
      points.add('Основные тезисы:');
      for (final p in mainPoints) {
        points.add('  • $p');
      }
    }

    // Вопросы для повторения
    final questions = _extractQuestions(text);
    if (questions.isNotEmpty) {
      points.add('Вопросы:');
      for (final q in questions.take(3)) {
        points.add('  ? $q');
      }
    }

    return SummaryResult(
      title: 'Конспект лекции',
      type: TextType.educational,
      points: points,
      fullText: text,
    );
  }

  // ========== Интервью ==========

  static SummaryResult _summarizeInterview(String text, List<String> sentences) {
    final questions = _extractQuestions(text);
    final quotes = _extractQuotes(text);
    final insights = _extractInsights(text);

    final points = <String>[];

    if (questions.isNotEmpty) {
      points.add('Вопросы:');
      for (final q in questions.take(5)) {
        points.add('  Q: $q');
      }
    }

    if (insights.isNotEmpty) {
      points.add('Инсайты:');
      for (final i in insights.take(5)) {
        points.add('  • $i');
      }
    }

    if (quotes.isNotEmpty) {
      points.add('Цитаты:');
      for (final q in quotes.take(3)) {
        points.add('  "${q.substring(0, math.min(100, q.length))}"');
      }
    }

    // Краткое содержание
    final summary = _textRankSummary(sentences, 3);
    if (summary.isNotEmpty) {
      points.add('Кратко:');
      for (final s in summary) {
        points.add('  • $s');
      }
    }

    return SummaryResult(
      title: 'Интервью',
      type: TextType.interview,
      points: points,
      fullText: text,
    );
  }

  // ========== Личные заметки ==========

  static SummaryResult _summarizePersonal(String text, List<String> sentences) {
    final ideas = _extractIdeas(text);
    final tasks = _extractTasks(text);
    final dates = _extractDates(text);

    final points = <String>[];

    if (ideas.isNotEmpty) {
      points.add('Идеи:');
      for (final i in ideas.take(5)) {
        points.add('  💡 $i');
      }
    }

    if (tasks.isNotEmpty) {
      points.add('Задачи:');
      for (final t in tasks.take(5)) {
        points.add('  □ $t');
      }
    }

    if (dates.isNotEmpty) {
      points.add('Даты:');
      for (final d in dates.take(3)) {
        points.add('  📅 $d');
      }
    }

    // Краткое содержание
    if (points.isEmpty) {
      final summary = _textRankSummary(sentences, 3);
      points.add('Заметки:');
      for (final s in summary) {
        points.add('  • $s');
      }
    }

    return SummaryResult(
      title: 'Личные заметки',
      type: TextType.personal,
      points: points,
      fullText: text,
      actionItems: tasks,
      dates: dates,
    );
  }

  // ========== Общий случай ==========

  static SummaryResult _summarizeGeneral(String text, List<String> sentences) {
    final summary = _textRankSummary(sentences, 5);
    final topics = _extractTopics(sentences, 3);

    final points = <String>[];

    if (topics.isNotEmpty) {
      points.add('Темы:');
      for (final t in topics) {
        points.add('  • $t');
      }
    }

    points.add('Ключевые мысли:');
    if (summary.isEmpty) {
      points.add('  • ${text.substring(0, math.min(200, text.length))}');
    } else {
      for (final p in summary) {
        points.add('  • $p');
      }
    }

    return SummaryResult(
      title: 'Саммари',
      type: TextType.general,
      points: points,
      fullText: text,
    );
  }

  // ========== Экстракторы данных ==========

  static List<String> _extractDecisions(String text) {
    final patterns = [
      RegExp(
        r'\b(решили|договорились|приняли решение|утвердили|согласовали|'
        r'назначили|определили|установили|поручили|поручил|поручила|'
        r'нужно сделать|необходимо|требуется|следует|будем делать|'
        r'планируем|собираемся|намерены|договорились о том|'
        r'пришли к выводу|согласились|одобрили|заключили)\b'
        r'[^.!?]{10,200}[.!?]?',
        caseSensitive: false,
      ),
    ];
    return _extractWithPatterns(text, patterns);
  }

  static List<String> _extractDeadlines(String text) {
    final patterns = [
      RegExp(
        r'\b(до\s+\d{1,2}[\.\s]\d{1,2}|в\s+\d{1,2}[\.\s]\d{1,2}|'
        r'к\s+\d{1,2}[\.\s]\d{1,2}|срок|дедлайн|'
        r'завтра|послезавтра|в\s+понедельник|во\s+вторник|'
        r'в\s+среду|в\s+четверг|в\s+пятницу|'
        r'в\s+субботу|в\s+воскресенье|'
        r'через\s+\d+\s+(дн|день|дня|час|часа|недел|неделю|месяц))\b'
        r'[^.!?]{5,150}[.!?]?',
        caseSensitive: false,
      ),
      RegExp(
        r'\d{1,2}[\.\-/]\d{1,2}[\.\-/]\d{2,4}',
      ),
    ];
    return _extractWithPatterns(text, patterns);
  }

  static List<String> _extractContacts(String text) {
    final patterns = [
      // Телефоны
      RegExp(
        r'(?:\+7|8)[\s\-]?\(?\d{3}\)?[\s\-]?\d{3}[\s\-]?\d{2}[\s\-]?\d{2}',
      ),
      // Email
      RegExp(
        r'[\w.+-]+@[\w-]+\.[\w.-]+',
      ),
      // Telegram
      RegExp(
        r'@\w{3,32}',
      ),
    ];
    return _extractWithPatterns(text, patterns);
  }

  static List<String> _extractAmounts(String text) {
    final patterns = [
      RegExp(
        r'\b\d+(?:\s*\d{3})*\s*(?:руб|рублей|₽|usd|usd|usd|usd|'
        r'тысяч|миллион|млн|тыс|k)\b'
        r'[^.!?]{0,30}',
        caseSensitive: false,
      ),
      RegExp(
        r'\b(?:цена|стоимость|сумма|бюджет|оплата|долг|за?\s+\d+)\b'
        r'[^.!?]{0,50}',
        caseSensitive: false,
      ),
    ];
    return _extractWithPatterns(text, patterns);
  }

  static List<String> _extractActionItems(String text) {
    final patterns = [
      RegExp(
        r'\b(нужно|необходимо|требуется|следует|важно|'
        r'не\s+забыть|обязательно|срочно|приоритет|'
        r'поручено|поручил|поручила|поручить|'
        r'сделать|выполнить|подготовить|написать|позвонить|'
        r'отправить|проверить|согласовать|утвердить)\b'
        r'[^.!?]{10,150}[.!?]?',
        caseSensitive: false,
      ),
    ];
    return _extractWithPatterns(text, patterns);
  }

  static List<String> _extractQuestions(String text) {
    final patterns = [
      RegExp(
        r'[^.!?]*\?',
      ),
    ];
    return _extractWithPatterns(text, patterns);
  }

  static List<String> _extractQuotes(String text) {
    final patterns = [
      RegExp(
        r'[\"\«]([^\"\»]{10,200})[\"\»]',
      ),
    ];
    final matches = patterns[0].allMatches(text);
    return matches.map((m) => m.group(1)!.trim()).toList();
  }

  static List<String> _extractInsights(String text) {
    final patterns = [
      RegExp(
        r'\b(самое\s+главное|ключевой\s+момент|важно\s+понимать|'
        r'главное|суть|смысл|вывод|итог|резюме|'
        r'мы\s+поняли|я\s+понял|осознал|понял|'
        r'интересно|удивительно|неожиданно|важно|'
        r'по-настоящему|на\s+самом\s+деле|в\s+действительности)\b'
        r'[^.!?]{10,200}[.!?]?',
        caseSensitive: false,
      ),
    ];
    return _extractWithPatterns(text, patterns);
  }

  static List<String> _extractIdeas(String text) {
    final patterns = [
      RegExp(
        r'\b(идея|придумал|подумал|вспомнил|заметил|'
        r'можно\s+сделать|можно\s+попробовать|'
        r'хорошо\s+бы|стоит\s+попробовать|'
        r'было\s+бы\s+круто|интересная\s+мысль|'
        r'возможно|предположим|представьте|'
        r'а\s+если\s+бы|а\s+что\s+если)\b'
        r'[^.!?]{10,200}[.!?]?',
        caseSensitive: false,
      ),
    ];
    return _extractWithPatterns(text, patterns);
  }

  static List<String> _extractTasks(String text) {
    return _extractActionItems(text); // tasks == action items for personal
  }

  static List<String> _extractDates(String text) {
    return _extractDeadlines(text); // dates == deadlines for personal
  }

  static List<String> _extractDefinitions(String text) {
    final patterns = [
      RegExp(
        r'\b([А-Я][а-яё\s]+)\s+(это|—|–|−|есть|представляет|'
        r'является|означает|обозначает)\s+'
        r'[^.!?]{10,200}[.!?]?',
        caseSensitive: false,
      ),
    ];
    return _extractWithPatterns(text, patterns);
  }

  static List<String> _extractKeyConcepts(String text) {
    final concepts = RegExp(
      r'\b[А-Я][а-яёA-Za-z\s\-]{2,30}\b|'
      r'"[^"]{2,30}"|'
      r'«[^»]{2,30}»',
    );

    final matches = concepts.allMatches(text);
    final unique = <String>{};
    for (final m in matches) {
      final concept = m.group(0)!.trim();
      if (concept.length > 3 && !_isCommonWord(concept)) {
        unique.add(concept);
      }
    }
    return unique.toList();
  }

  static List<String> _extractTopics(List<String> sentences, int count) {
    if (sentences.length <= count) return sentences;

    // Берём предложения с ключевыми существительными (темы)
    final scored = sentences.map((s) {
      final words = s.toLowerCase().split(RegExp(r'\s+'));
      var score = 0;
      for (final w in words) {
        if (w.isNotEmpty && w[0] == w[0].toUpperCase() && w.length > 3) {
          score += 2; // заглавные слова = темы
        }
        if (_topicIndicators.contains(w)) {
          score += 3; // индикаторы тем
        }
      }
      return {'sentence': s, 'score': score};
    }).toList();

    scored.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
    return scored.take(count).map((e) => e['sentence'] as String).toList();
  }

  static final Set<String> _topicIndicators = {
    'тема', 'тему', 'вопрос', 'вопросу', 'проблема', 'проблему',
    'задача', 'задачу', 'цель', 'цели', 'тема', 'тему',
    'обсуждали', 'говорили', 'разговор', 'обсуждение',
  };

  static List<String> _extractWithPatterns(String text, List<RegExp> patterns) {
    final results = <String>{};
    for (final pattern in patterns) {
      final matches = pattern.allMatches(text);
      for (final m in matches) {
        final match = m.group(0)!.trim();
        if (match.length > 5) {
          results.add(match);
        }
      }
    }
    return results.toList();
  }

  // ========== TextRank ==========

  static List<String> _textRankSummary(List<String> sentences, int count) {
    if (sentences.length <= count) return sentences;

    final wordsPerSentence = sentences.map((s) =>
      s.toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && !_isStopWord(w))
        .toList()
    ).toList();

    final wordFreq = <String, int>{};
    for (final words in wordsPerSentence) {
      for (final w in words) {
        wordFreq[w] = (wordFreq[w] ?? 0) + 1;
      }
    }

    final weights = <double>[];
    for (int i = 0; i < sentences.length; i++) {
      double weight = 0;
      for (int j = 0; j < sentences.length; j++) {
        if (i == j) continue;
        weight += _similarity(wordsPerSentence[i], wordsPerSentence[j], wordFreq);
      }
      weights.add(weight);
    }

    final indexed = List.generate(sentences.length, (i) =>
      {'index': i, 'weight': weights[i]}
    );
    indexed.sort((a, b) => (b['weight'] as double).compareTo(a['weight'] as double));

    final topIndices = indexed
        .take(count)
        .map((e) => e['index'] as int)
        .toList()
      ..sort();

    return topIndices.map((i) => sentences[i]).toList();
  }

  static double _similarity(List<String> a, List<String> b, Map<String, int> freq) {
    final all = <String>{...a, ...b};
    double dot = 0, normA = 0, normB = 0;

    for (final w in all) {
      final idf = math.log(1 + (freq[w] ?? 0));
      final wa = a.where((x) => x == w).length * idf;
      final wb = b.where((x) => x == w).length * idf;
      dot += wa * wb;
      normA += wa * wa;
      normB += wb * wb;
    }

    if (normA == 0 || normB == 0) return 0;
    return dot / (math.sqrt(normA) * math.sqrt(normB));
  }

  // ========== Утилиты ==========

  static List<String> _splitIntoSentences(String text) {
    // Разбиваем по точкам/восклицательным/вопросительным
    final pattern = RegExp(r'[.!?]+\s*');
    var sentences = text
        .split(pattern)
        .map((s) => s.trim())
        .where((s) => s.length > 3)
        .toList();

    // Если мало предложений — режем по длине
    if (sentences.length <= 2 && text.length > 40) {
      final words = text.split(RegExp(r'\s+'));
      sentences = [];
      final chunkSize = words.length <= 20 ? 8 : 12;
      for (int i = 0; i < words.length; i += chunkSize) {
        final end = (i + chunkSize).clamp(0, words.length);
        final chunk = words.sublist(i, end).join(' ');
        if (chunk.length > 3) sentences.add(chunk);
      }
    }

    return sentences;
  }

  static bool _isCommonWord(String word) {
    const common = {
      'этот', 'тот', 'такой', 'какой', 'который', 'которая', 'которые',
      'один', 'два', 'три', 'первый', 'второй', 'третий',
      'только', 'даже', 'уже', 'ещё', 'всё', 'все', 'ничего',
      'здесь', 'там', 'тут', 'где', 'когда', 'потому', 'поэтому',
    };
    return common.contains(word.toLowerCase());
  }

  static bool _isStopWord(String word) {
    const stopWords = {
      'и', 'в', 'во', 'не', 'что', 'он', 'на', 'я', 'с', 'со', 'как', 'а', 'то',
      'все', 'она', 'так', 'его', 'но', 'да', 'ты', 'к', 'у', 'же', 'вы', 'за',
      'бы', 'по', 'только', 'ее', 'мне', 'было', 'вот', 'от', 'меня', 'еще',
      'нет', 'о', 'из', 'ему', 'теперь', 'когда', 'даже', 'ну', 'вдруг', 'ли',
      'если', 'уже', 'или', 'ни', 'быть', 'был', 'него', 'до', 'вас', 'нибудь',
      'опять', 'уж', 'вам', 'ведь', 'там', 'потом', 'себя', 'ничего', 'ей',
      'может', 'они', 'тут', 'где', 'есть', 'надо', 'ней', 'для', 'мы', 'тебя',
      'их', 'чем', 'была', 'сам', 'чтоб', 'без', 'будто', 'чего', 'раз',
      'тоже', 'себе', 'под', 'будет', 'ж', 'тогда', 'кто', 'этот', 'того',
      'потому', 'этого', 'какой', 'совсем', 'ним', 'здесь', 'этом', 'один',
      'почти', 'мой', 'тем', 'чтобы', 'нее', 'сейчас', 'были', 'куда',
      'зачем', 'всех', 'можно', 'про', 'наконец', 'два', 'об', 'другой',
      'хоть', 'после', 'над', 'больше', 'тот', 'через', 'эти', 'нас',
      'всего', 'них', 'какая', 'много', 'разве', 'три', 'эту', 'моя',
      'впрочем', 'хорошо', 'свою', 'этой', 'перед', 'иногда', 'лучше',
      'чуть', 'том', 'нельзя', 'такой', 'им', 'более', 'всегда', 'конечно',
      'всю', 'между',
    };
    return stopWords.contains(word.toLowerCase());
  }
}

// ========== Типы данных ==========

enum TextType {
  narrative,    // Сказка, история (fallback)
  business,     // Совещание, деловой разговор
  educational,  // Лекция, урок
  interview,    // Интервью
  personal,     // Личные заметки
  general,      // Общий случай
}

class SummaryResult {
  final String title;
  final TextType type;
  final List<String> points;
  final String fullText;
  final List<String> actionItems;
  final List<String> contacts;
  final List<String> deadlines;
  final List<String> amounts;
  final List<String> dates;

  SummaryResult({
    required this.title,
    required this.type,
    required this.points,
    required this.fullText,
    this.actionItems = const [],
    this.contacts = const [],
    this.deadlines = const [],
    this.amounts = const [],
    this.dates = const [],
  });

  factory SummaryResult.empty() => SummaryResult(
    title: 'Нет данных',
    type: TextType.general,
    points: ['Текст слишком короткий для саммари'],
    fullText: '',
  );

  String get formatted {
    final buffer = StringBuffer();
    buffer.writeln('=== $title ===');
    buffer.writeln();
    for (final point in points) {
      buffer.writeln(point);
    }
    return buffer.toString();
  }

  String get typeLabel {
    switch (type) {
      case TextType.business: return 'Бизнес-встреча';
      case TextType.educational: return 'Лекция / Образование';
      case TextType.interview: return 'Интервью';
      case TextType.personal: return 'Личные заметки';
      case TextType.narrative: return 'История / Рассказ';
      case TextType.general: return 'Общая запись';
    }
  }
}
