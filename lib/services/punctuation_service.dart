import 'NameDictionary.dart';

/// PunctuationService v35-fix — восстановлена логика v34 для разбиения на предложения,
/// сохранены NameDictionary, вопросы/восклицания, корректная обработка предлогов.
class PunctuationService {
  static const double pauseThreshold = 0.4;
  static const int minWordsPerSentence = 5;
  static const int maxWordsPerSentence = 12;
  static const int hardLimit = 18;

  // Слова, после которых НЕ ставим точку и НЕ разрываем предложение
  static final Set<String> tailWords = {
    'и', 'или', 'но', 'а', 'что', 'когда', 'если', 'потому', 'поэтому',
    'как', 'так', 'чтобы', 'хотя', 'пока', 'после', 'перед', 'будто',
    'например', 'однако', 'также', 'следовательно', 'во-первых', 'во-вторых',
    'в-третьих', 'наконец', 'кроме', 'более', 'менее', 'между', 'прочим',
    'кстати', 'вообще', 'вероятно', 'видимо', 'очевидно', 'действительно',
    'пожалуй', 'конечно', 'безусловно', 'несомненно', 'возможно',
    'можно', 'нужно', 'нельзя', 'будем', 'будет', 'может', 'должны',
    'следует', 'стоит', 'пора', 'пришлось', 'придется',
    'да', 'либо', 'нибудь', 'тоже', 'зато',
    'тем', 'ибо', 'лишь', 'только',
    'со', 'про', 'изо', 'пред', 'ради', 'вроде', 'вопреки', 'посредством',
    'вместо', 'вследствие', 'ввиду', 'вслед', 'согласно',
    'помимо', 'несмотря', 'внутри', 'вне', 'благодаря', 'спустя', 'среди',
    'близ', 'мимо', 'поперёк', 'сквозь', 'вглубь', 'вдоль',
    'вокруг', 'впереди', 'вовне', 'внутрь', 'не', 'ни', 'обо', 'ото',
    'передо', 'подо', 'поперек', 'сверх', 'снизу', 'вперед',
    'собственно', 'по-видимому',
    'быть', 'есть', 'является', 'являются', 'означает', 'означают',
    'представляет', 'представляют', 'обозначает', 'обозначают',
    'состоит', 'состоят', 'включает', 'включают', 'содержит', 'содержат',
    'оказывается', 'оказываются', 'получается', 'получаются',
    'говорится', 'говорят', 'думается', 'думают', 'считается', 'считаются',
    'полагается', 'полагают', 'предполагается', 'предполагаются',
    'предположим', 'допустим', 'пусть', 'даже', 'всё', 'все',
  };

  // Предлоги — не разрываем предложение после/перед ними
  static final Set<String> prepositions = {
    'в', 'на', 'с', 'по', 'к', 'у', 'о', 'об', 'от', 'для',
    'за', 'под', 'над', 'при', 'перед', 'через', 'между',
    'из', 'до', 'после', 'без', 'около', 'возле', 'против',
    'со', 'про', 'изо', 'пред', 'ради', 'вопреки', 'посредством',
    'вместо', 'вследствие', 'ввиду', 'вслед', 'согласно',
    'помимо', 'несмотря', 'внутри', 'вне', 'благодаря', 'спустя', 'среди',
    'близ', 'мимо', 'поперёк', 'сквозь', 'вглубь', 'вдоль',
    'вокруг', 'впереди', 'вовне', 'внутрь', 'обо', 'ото',
    'передо', 'подо', 'поперек', 'сверх', 'снизу',
  };

  // ===== QUESTION PATTERNS =====
  static final List<RegExp> questionPatterns = [
    RegExp(r'\b(сколько|что|как|почему|зачем|кто|где|когда|куда|откуда|какой|чей)\b', caseSensitive: false),
    RegExp(r'\b(вы\s+примете|вы\s+похожи|вы\s+знаете|вы\s+понимаете|вы\s+согласны)\b', caseSensitive: false),
    RegExp(r'\b(спросил|спросила|задал\s+вопрос|вопрос|интересно)\b', caseSensitive: false),
  ];

  // ===== EXCLAMATION PATTERNS =====
  static final List<RegExp> exclamationPatterns = [
    RegExp(r'\b(сын\s+мой|дочь\s+моя|мать\s+моя|отец\s+мой|боже|господи|чёрт|черт|ура|ой|ах|ох)\b', caseSensitive: false),
    RegExp(r'\b(прижала|обняла|поцеловала|воскликнул|воскликнула|крикнул|крикнула|закричал|закричала)\b', caseSensitive: false),
  ];

  static bool isTailWord(String word) {
    return tailWords.contains(word.toLowerCase());
  }

  static bool isPreposition(String word) {
    return prepositions.contains(word.toLowerCase());
  }

  static bool isQuestion(String text) {
    for (var pattern in questionPatterns) {
      if (pattern.hasMatch(text)) return true;
    }
    return false;
  }

  static bool isExclamation(String text) {
    for (var pattern in exclamationPatterns) {
      if (pattern.hasMatch(text)) return true;
    }
    return false;
  }

  /// Wrapper для совместимости с v34 — конвертирует String в размеченный текст.
  /// НЕ использует фиксированные тайминги: разбиение происходит по длине предложения
  /// и логике союзов/предлогов.
  static String addPunctuationToText(String text) {
    if (text == 'PUNCT_TEST') return 'PUNCT_TEST_v35';
    if (text.isEmpty) return text;

    final words = text.trim().split(RegExp(r'\s+'));
    if (words.isEmpty) return '';

    final sentences = <String>[];
    final currentSentence = <String>[];

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      final nextWord = (i + 1 < words.length) ? words[i + 1].toLowerCase() : '';

      if (currentSentence.isNotEmpty) {
        final lastWord = currentSentence.last.toLowerCase();
        final lastWordIsConnector = isTailWord(lastWord) || isPreposition(lastWord);
        final nextWordIsConnector = isTailWord(nextWord) || isPreposition(nextWord);
        final sentenceTooLong = currentSentence.length >= maxWordsPerSentence;
        final tooShort = currentSentence.length < minWordsPerSentence;
        final hardLimitHit = currentSentence.length >= hardLimit;

        if (hardLimitHit) {
          sentences.add(finishSentence(currentSentence));
          currentSentence.clear();
        } else if (sentenceTooLong && !lastWordIsConnector && !nextWordIsConnector && !tooShort) {
          sentences.add(finishSentence(currentSentence));
          currentSentence.clear();
        }
      }

      // Применяем NameDictionary
      final displayWord = NameDictionary.isProperNoun(word) ? NameDictionary.capitalize(word) : word;
      currentSentence.add(displayWord);
    }

    if (currentSentence.isNotEmpty) {
      sentences.add(finishSentence(currentSentence));
    }

    return sentences.join(' ');
  }

  /// Разметка с использованием реальных таймингов из VOSK (динамический threshold)
  static String addPunctuation(List<WordTiming> words) {
    if (words.isEmpty) return '';
    final threshold = calculateDynamicThreshold(words);

    final sentences = <String>[];
    final currentSentence = <String>[];
    double lastEndTime = 0;

    for (var wordTiming in words) {
      final word = wordTiming.word;
      final pauseDetected = lastEndTime > 0 && (wordTiming.start - lastEndTime) > threshold;
      final sentenceTooLong = currentSentence.length >= maxWordsPerSentence;

      final lastWord = currentSentence.isNotEmpty ? currentSentence.last.toLowerCase() : '';
      final lastWordIsConnector = isTailWord(lastWord) || isPreposition(lastWord);
      final nextWord = word.toLowerCase();
      final nextWordIsConnector = isTailWord(nextWord) || isPreposition(nextWord);
      final tooShort = currentSentence.length < minWordsPerSentence;

      if ((pauseDetected || sentenceTooLong) && !lastWordIsConnector && !nextWordIsConnector && !tooShort) {
        if (currentSentence.isNotEmpty) {
          sentences.add(finishSentence(currentSentence));
          currentSentence.clear();
        }
      }

      // NameDictionary
      final displayWord = NameDictionary.isProperNoun(word) ? NameDictionary.capitalize(word) : word;
      currentSentence.add(displayWord);

      lastEndTime = wordTiming.end;
    }

    if (currentSentence.isNotEmpty) {
      sentences.add(finishSentence(currentSentence));
    }

    return sentences.join(' ');
  }

  static double calculateDynamicThreshold(List<WordTiming> words) {
    if (words.length < 3) return 0.4;
    final pauses = <double>[];
    for (int i = 1; i < words.length; i++) {
      final pause = words[i].start - words[i - 1].end;
      if (pause > 0.01) pauses.add(pause);
    }
    if (pauses.isEmpty) return 0.4;
    pauses.sort();
    final median = pauses[pauses.length ~/ 2];
    return (median * 2).clamp(0.3, 1.5);
  }

  static String finishSentence(List<String> words) {
    String text = words.join(' ');
    if (text.isEmpty) return '';

    // Заглавная первая буква
    text = text[0].toUpperCase() + text.substring(1);

    // Определяем пунктуацию
    if (isExclamation(text)) {
      if (!text.endsWith('!')) text += '!';
    } else if (isQuestion(text)) {
      if (!text.endsWith('?')) text += '?';
    } else {
      if (!text.endsWith('.') && !text.endsWith('?') && !text.endsWith('!')) {
        text += '.';
      }
    }
    return text;
  }
}

class WordTiming {
  final String word;
  final double start;
  final double end;

  WordTiming(this.word, this.start, this.end);
}
