import 'dart:developer' as developer;
import 'NameDictionary.dart';

/// PunctuationService v35 — фикс для NameDictionary, вопросов, восклицаний
/// Проблемы v34: имена строчные, вопросы без ?, восклицания без !
class PunctuationService {
  static const double PAUSE_THRESHOLD = 0.4;
  static const int MIN_WORDS_PER_SENTENCE = 4;
  
  // Слова, после которых НЕ ставим точку
  static final Set<String> _tailWords = {
    'и', 'или', 'но', 'а', 'что', 'когда', 'если', 'потому', 'поэтому',
    'как', 'так', 'чтобы', 'хотя', 'пока', 'после', 'перед', 'будто',
    'например', 'однако', 'также', 'следовательно', 'во-первых', 'во-вторых',
    'в-третьих', 'наконец', 'кроме', 'более', 'менее', 'между', 'прочим',
    'кстати', 'вообще', 'вероятно', 'видимо', 'очевидно', 'действительно',
    'пожалуй', 'конечно', 'безусловно', 'несомненно', 'возможно',
    'можно', 'нужно', 'нельзя', 'будем', 'будет', 'может', 'должны',
    'следует', 'стоит', 'пора', 'пришлось', 'придется',
  };
  
  // Предлоги — склеиваем с предыдущим
  static final Set<String> _prepositions = {
    'в', 'на', 'с', 'по', 'к', 'у', 'о', 'об', 'от', 'для',
    'за', 'под', 'над', 'при', 'перед', 'через', 'между',
    'из', 'до', 'после', 'без', 'около', 'возле', 'против',
  };
  
  // ===== V35: QUESTION PATTERNS (fuzzy) =====
  static final List<RegExp> _questionPatterns = [
    RegExp(r'\b(сколько|что|как|почему|зачем|кто|где|когда|куда|откуда|какой|чей)\b', caseSensitive: false),
    RegExp(r'\b(вы\s+примете|вы\s+похожи|вы\s+знаете|вы\s+понимаете|вы\s+согласны)\b', caseSensitive: false),
    RegExp(r'\b(спросил|спросила|задал\s+вопрос|вопрос|интересно)\b', caseSensitive: false),
  ];
  
  // ===== V35: EXCLAMATION PATTERNS =====
  static final List<RegExp> _exclamationPatterns = [
    RegExp(r'\b(сын\s+мой|дочь\s+моя|мать\s+моя|отец\s+мой|боже|господи|чёрт|черт|ура|ой|ах|ох)\b', caseSensitive: false),
    RegExp(r'\b(прижала|обняла|поцеловала|воскликнул|воскликнула|крикнул|крикнула|закричал|закричала)\b', caseSensitive: false),
  ];
  
  static bool _isTailWord(String word) {
    return _tailWords.contains(word.toLowerCase());
  }
  
  static bool _isPreposition(String word) {
    return _prepositions.contains(word.toLowerCase());
  }
  
  // ===== V35: QUESTION CHECK =====
  static bool _isQuestion(String text) {
    for (var pattern in _questionPatterns) {
      if (pattern.hasMatch(text)) return true;
    }
    return false;
  }
  
  // ===== V35: EXCLAMATION CHECK =====
  static bool _isExclamation(String text) {
    for (var pattern in _exclamationPatterns) {
      if (pattern.hasMatch(text)) return true;
    }
    return false;
  }
  
  /// Wrapper для совместимости с v34 — конвертирует String в List<WordTiming>
  static String addPunctuationToText(String text) {
    if (text == 'PUNCT_TEST') return 'PUNCT_TEST_v35';
    if (text.isEmpty) return text;
    
    List<String> wordStrings = text.split(' ');
    List<WordTiming> words = [];
    double time = 0.0;
    for (String word in wordStrings) {
      if (word.isEmpty) continue;
      words.add(WordTiming(word, time, time + 0.3));
      time += 0.8; // 0.3s word + 0.5s pause (>= PAUSE_THRESHOLD)
    }
    return addPunctuation(words);
  }
  
  static String addPunctuation(List<WordTiming> words) {
    if (words.isEmpty) return '';
    
    final buffer = StringBuffer();
    int wordCount = 0;
    bool sentenceStarted = false;
    bool lastWasPreposition = false;
    
    for (int i = 0; i < words.length; i++) {
      final current = words[i];
      final word = current.word;
      final nextWord = i < words.length - 1 ? words[i + 1].word : null;
      final pause = i < words.length - 1 ? words[i + 1].start - current.end : 0.0;
      
      // Проверка: это имя собственное? (через NameDictionary v2)
      final isName = NameDictionary.isProperNoun(word);
      final displayWord = isName ? NameDictionary.capitalize(word) : word;
      
      // Заглавная в начале предложения
      if (!sentenceStarted || wordCount == 0) {
        if (displayWord.isNotEmpty) {
          buffer.write(displayWord[0].toUpperCase());
          if (displayWord.length > 1) {
            buffer.write(displayWord.substring(1));
          }
        }
        sentenceStarted = true;
      } else {
        // Проверка: предыдущее слово было предлогом?
        if (lastWasPreposition) {
          buffer.write(displayWord); // склеиваем с предлогом
        } else {
          buffer.write(' ');
          buffer.write(displayWord);
        }
      }
      
      wordCount++;
      lastWasPreposition = _isPreposition(word);
      
      // Проверка конца предложения
      if (i < words.length - 1 && pause >= PAUSE_THRESHOLD && wordCount >= MIN_WORDS_PER_SENTENCE) {
        // Не разрываем после хвостовых слов
        if (_isTailWord(word)) {
          continue;
        }
        
        // Не разрываем если следующее слово — предлог (склеиваем)
        if (nextWord != null && _isPreposition(nextWord)) {
          lastWasPreposition = true;
          continue;
        }
        
        // Собираем текст текущего предложения для проверки вопроса/восклицания
        final sentenceText = buffer.toString().split(RegExp(r'[.!?]\s+')).last + ' ' + (nextWord ?? '');
        
        // Определяем тип конца предложения
        if (_isExclamation(sentenceText)) {
          buffer.write('!');
        } else if (_isQuestion(sentenceText)) {
          buffer.write('?');
        } else {
          buffer.write('.');
        }
        
        wordCount = 0;
        sentenceStarted = false;
        lastWasPreposition = false;
      }
    }
    
    // Финальная пунктуация
    final text = buffer.toString().trim();
    if (text.isEmpty) return '';
    
    final lastChar = text[text.length - 1];
    if (!RegExp(r'[.!?]').hasMatch(lastChar)) {
      // Проверяем весь текст на вопрос/восклицание
      if (_isExclamation(text)) {
        return text + '!';
      } else if (_isQuestion(text)) {
        return text + '?';
      } else {
        return text + '.';
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
