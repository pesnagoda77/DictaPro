// NameDictionary v2 — fuzzy matching для VOSK-вариантов
// Проблема v34: VOSK выдаёт "феодор" вместо "Фёдор", "генри" вместо "Генри"

class NameDictionary {
  static final Map<String, List<String>> _dictionary = {
    // О. Генри — персонажи
    'феодор': ['Фёдор', 'Федор'],
    'федор': ['Фёдор', 'Федор'],
    'генри': ['Генри'],
    'ларедо': ['Ларедо'],
    'техас': ['Техас'],
    'корпус': ['Корпус'],
    'кристи': ['Кристи'],
    'капитан': ['Капитан'],
    'бун': ['Бун'],
    'ван': ['Ван'],
    'она': ['Она'],
    'кентукки': ['Кентукки'],
    'уреки': ['У реки'],
    'такер': ['Такер', 'Тэккер', 'Трекер'],
    'тэккер': ['Такер', 'Тэккер', 'Трекер'],
    'трекер': ['Такер', 'Тэккер', 'Трекер'],
    'хаус': ['Хаус'],
    'вальда': ['Вальда'],
    'ландо': ['Ландо'],
    'андрей': ['Андрей'],
    'клайда': ['Клайда'],
    'сеньор': ['Сеньор'],
    'сеньориты': ['Сеньориты'],
    'касса': ['Касса'],
    'ланка': ['Ланка'],
    'боин': ['Боин'],
    'басков': ['Басков'],
    'миллер': ['Миллер'],
    'конца': ['Конца'],
    'алиса': ['Алиса'],
    'новый': ['Новый'],
    'орлеан': ['Орлеан'],
    'сандакан': ['Сандакан'],
    
    // Общие имена
    'александр': ['Александр'],
    'алексей': ['Алексей'],
    'борис': ['Борис'],
    'владимир': ['Владимир'],
    'дмитрий': ['Дмитрий'],
    'евгений': ['Евгений'],
    'иван': ['Иван'],
    'михаил': ['Михаил'],
    'николай': ['Николай'],
    'павел': ['Павел'],
    'петр': ['Пётр'],
    'сергей': ['Сергей'],
    'юрий': ['Юрий'],
  };
  
  /// Проверяет, является ли слово именем собственным (fuzzy matching)
  static bool isProperNoun(String word) {
    final lower = word.toLowerCase().replaceAll('ё', 'е');
    
    // Прямое совпадение
    if (_dictionary.containsKey(lower)) return true;
    
    // Проверка по вариантам (на случай если VOSK выдал "феодор" а у нас "федор")
    for (var entry in _dictionary.entries) {
      final key = entry.key;
      // Расстояние Левенштейна ≤ 2 или вхождение
      if (_levenshtein(lower, key) <= 2) return true;
      if (lower.contains(key) || key.contains(lower)) return true;
    }
    
    return false;
  }
  
  /// Возвращает правильное написание имени
  static String capitalize(String word) {
    final lower = word.toLowerCase().replaceAll('ё', 'е');
    
    if (_dictionary.containsKey(lower)) {
      return _dictionary[lower]!.first;
    }
    
    // Fuzzy поиск
    for (var entry in _dictionary.entries) {
      if (_levenshtein(lower, entry.key) <= 2 || 
          lower.contains(entry.key) || 
          entry.key.contains(lower)) {
        return entry.value.first;
      }
    }
    
    // Fallback: просто заглавная первая буква
    if (word.isEmpty) return word;
    return word[0].toUpperCase() + word.substring(1);
  }
  
  /// Расстояние Левенштейна (для fuzzy matching)
  static int _levenshtein(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    
    final rows = a.length + 1;
    final cols = b.length + 1;
    final matrix = List.generate(rows, (_) => List.filled(cols, 0));
    
    for (int i = 0; i < rows; i++) matrix[i][0] = i;
    for (int j = 0; j < cols; j++) matrix[0][j] = j;
    
    for (int i = 1; i < rows; i++) {
      for (int j = 1; j < cols; j++) {
        final cost = (a[i - 1] == b[j - 1]) ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1,      // deletion
          matrix[i][j - 1] + 1,      // insertion
          matrix[i - 1][j - 1] + cost, // substitution
        ].reduce((min, val) => val < min ? val : min);
      }
    }
    
    return matrix[a.length][b.length];
  }
  
  /// Добавить новое имя в словарь
  static void addName(String voskVariant, String correctForm) {
    final key = voskVariant.toLowerCase().replaceAll('ё', 'е');
    if (_dictionary.containsKey(key)) {
      _dictionary[key]!.add(correctForm);
    } else {
      _dictionary[key] = [correctForm];
    }
  }
  
  /// Получить все имена (для отладки)
  static Map<String, List<String>> get dictionary => 
      Map.unmodifiable(_dictionary);
}