class PunctuationService {
  static const int MAX_WORDS_PER_SENTENCE = 12;
  static const int MIN_WORDS_PER_SENTENCE = 5;

  // Слова, после которых НЕ разрываем предложение, даже если пауза длинная
  static const Set<String> noBreakWords = {
    // Союзы
    'и', 'или', 'но', 'а', 'да', 'либо', 'нибудь', 'тоже', 'также', 'зато',
    'когда', 'пока', 'если', 'хотя', 'так', 'чтобы', 'что', 'потому',
    'поэтому', 'тем', 'ибо', 'лишь', 'только', 'как',
    // Предлоги
    'после', 'перед', 'для', 'с', 'со', 'от', 'до', 'по', 'под', 'при',
    'в', 'во', 'на', 'за', 'к', 'ко', 'о', 'об', 'про', 'через', 'из', 'изо',
    'между', 'над', 'пред', 'ради', 'вроде', 'вопреки', 'посредством',
    'кроме', 'без', 'безо', 'вместо', 'вследствие', 'ввиду', 'вслед', 'согласно',
    'помимо', 'несмотря', 'внутри', 'вне', 'благодаря', 'спустя', 'среди',
    'близ', 'мимо', 'около', 'поперёк', 'сквозь', 'вглубь', 'вдоль', 'возле',
    'вокруг', 'впереди', 'вовне', 'внутрь', 'у', 'не', 'ни', 'обо', 'ото',
    'передо', 'подо', 'поперек', 'сверх', 'снизу', 'вперед',
    // Вводные слова
    'например', 'однако', 'следовательно', 'во-первых', 'во-вторых',
    'в-третьих', 'вообще', 'вероятно', 'видимо', 'очевидно', 'кстати',
    'собственно', 'действительно', 'возможно', 'по-видимому', 'пожалуй',
    // Начальные конструкции
    'может', 'можно', 'нужно', 'будем', 'будет', 'будут', 'быть', 'есть',
    'является', 'являются', 'означает', 'означают', 'представляет',
    'представляют', 'обозначает', 'обозначают', 'состоит', 'состоят',
    'включает', 'включают', 'содержит', 'содержат', 'следует', 'следуют',
    'оказывается', 'оказываются', 'получается', 'получаются',
    'говорится', 'говорят', 'думается', 'думают', 'считается', 'считаются',
    'полагается', 'полагают', 'предполагается', 'предполагаются',
    'предположим', 'допустим', 'пусть', 'даже', 'всё', 'все',
  };

  static double _calculateDynamicThreshold(List<WordTiming> words) {
    if (words.length < 3) return 0.4;
    final pauses = <double>[];
    for (int i = 1; i < words.length; i++) {
      final pause = words[i].startTime - words[i - 1].endTime;
      if (pause > 0.01) pauses.add(pause);
    }
    if (pauses.isEmpty) return 0.4;
    pauses.sort();
    final median = pauses[pauses.length ~/ 2];
    return (median * 2).clamp(0.3, 1.5);
  }

  static String addPunctuation(List<WordTiming> words) {
    if (words.isEmpty) return '';
    final threshold = _calculateDynamicThreshold(words);

    List<String> sentences = [];
    List<String> currentSentence = [];
    double lastEndTime = 0;

    for (var word in words) {
      bool pauseDetected = lastEndTime > 0 && (word.startTime - lastEndTime) > threshold;
      bool sentenceTooLong = currentSentence.length >= MAX_WORDS_PER_SENTENCE;

      // Не разрываем, если последнее слово — союз/предлог/вводное
      String lastWord = currentSentence.isNotEmpty ? currentSentence.last.toLowerCase() : '';
      bool lastWordIsConnector = noBreakWords.contains(lastWord);

      // Не разрываем, если следующее слово — союз/предлог/вводное (продолжение фразы)
      String nextWord = word.text.toLowerCase();
      bool nextWordIsConnector = noBreakWords.contains(nextWord);

      // Минимум 5 слов в предложении
      bool tooShort = currentSentence.length < MIN_WORDS_PER_SENTENCE;

      if ((pauseDetected || sentenceTooLong) && !lastWordIsConnector && !nextWordIsConnector && !tooShort) {
        if (currentSentence.isNotEmpty) {
          sentences.add(_finishSentence(currentSentence));
          currentSentence = [];
        }
      }

      currentSentence.add(word.text);
      lastEndTime = word.endTime;
    }

    if (currentSentence.isNotEmpty) {
      sentences.add(_finishSentence(currentSentence));
    }

    return sentences.join(' ');
  }

  static String addPunctuationToText(String text) {
    print('DEBUG: PunctuationService.addPunctuationToText called with ${text.length} chars');
    if (text.isEmpty) return '';

    final words = text.trim().split(RegExp(r'\s+'));
    print('DEBUG: Split into ${words.length} words');
    if (words.isEmpty) return '';

    final sentences = <String>[];
    final currentSentence = <String>[];

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      final nextWord = (i + 1 < words.length) ? words[i + 1].toLowerCase() : '';

      if (currentSentence.isNotEmpty) {
        final lastWord = currentSentence.last.toLowerCase();
        final bool lastWordIsConnector = noBreakWords.contains(lastWord);
        final bool nextWordIsConnector = noBreakWords.contains(nextWord);
        final bool sentenceTooLong = currentSentence.length >= MAX_WORDS_PER_SENTENCE;
        final bool tooShort = currentSentence.length < MIN_WORDS_PER_SENTENCE;
        final bool hardLimit = currentSentence.length >= 18;

        if (hardLimit) {
          sentences.add(_finishSentence(currentSentence));
          currentSentence.clear();
        } else if (sentenceTooLong && !lastWordIsConnector && !nextWordIsConnector && !tooShort) {
          sentences.add(_finishSentence(currentSentence));
          currentSentence.clear();
        }
      }

      currentSentence.add(word);
    }

    if (currentSentence.isNotEmpty) {
      sentences.add(_finishSentence(currentSentence));
    }

    final result = sentences.join(' ');
    print('DEBUG: PunctuationService output: ${result.length} chars, ${sentences.length} sentences');
    return result;
  }

  static String _finishSentence(List<String> words) {
    String text = words.join(' ');
    if (text.isEmpty) return '';
    text = text[0].toUpperCase() + text.substring(1);
    if (!text.endsWith('.') && !text.endsWith('?') && !text.endsWith('!')) {
      text += '.';
    }
    return text;
  }
}

class WordTiming {
  final String text;
  final double startTime;
  final double endTime;

  WordTiming(this.text, this.startTime, this.endTime);
}
