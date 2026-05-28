class VoskAutoCorrectionExtended {
  static const Map<String, String> commonMistakes = {
    // Разрывы слов
    'рос космос': 'Роскосмос',
    'кос монавт': 'космонавт',
    'кос монавтика': 'космонавтика',
    'бес пилотник': 'беспилотник',
    'космо дром': 'космодром',
    'ра кета': 'ракета',
    'спу тник': 'спутник',
    'ор бита': 'орбита',
    'за пуск': 'запуск',
    'по садка': 'посадка',
    'сты ковка': 'стыковка',
    'бес пилотный': 'беспилотный',
    
    // Пропущенные/лишние буквы
    'табачного': 'табачного',
    'воссозданию': 'воссозданию',
    'вос созданию': 'воссозданию',
    'я дерных': 'ядерных',
    'опы т': 'опыт',
    
    // Города
    'питер': 'Петербург',
    'мск': 'Москва',
    'нск': 'Новосибирск',
    'екб': 'Екатеринбург',
    
    // Бренды
    'газ пром': 'Газпром',
    'лук ойл': 'Лукойл',
    'рос нефть': 'Роснефть',
    'сбер банк': 'Сбербанк',
    'тинькофф': 'Тинькофф',
    'яндекс': 'Яндекс',
    
    // IT
    'джава': 'Java',
    'питон': 'Python',
    'джаваскрипт': 'JavaScript',
    'тайпскрипт': 'TypeScript',
    'реакт': 'React',
    'нод': 'Node.js',
    'докер': 'Docker',
    'линукс': 'Linux',
    'гитхаб': 'GitHub',
    
    // Медицина
    'мрт': 'МРТ',
    'кт': 'КТ',
    'узи': 'УЗИ',
    'лор': 'ЛОР',
    'рентген': 'рентген',
    
    // Юриспруденция
    'уголовный кодекс': 'Уголовный кодекс',
    'гражданский кодекс': 'Гражданский кодекс',
    'административный кодекс': 'Административный кодекс',
    
    // Частые замены
    'космос': 'космос',
    'орбита': 'орбита',
    'ракета': 'ракета',
    'спутник': 'спутник',
    'запуск': 'запуск',
    'посадка': 'посадка',
    'стыковка': 'стыковка',
  };

  static String correct(String text) {
    String result = text;
    
    // 1. Прямая замена по словарю
    for (final entry in commonMistakes.entries) {
      result = result.replaceAll(
        RegExp(entry.key, caseSensitive: false),
        entry.value,
      );
    }
    
    // 2. Замена по регексам (для сложных паттернов)
    result = result.replaceAllMapped(
      RegExp(r'(\S)\s+(\S)', caseSensitive: false),
      (match) {
        String combined = '${match.group(1)}${match.group(2)}'.toLowerCase();
        for (final entry in commonMistakes.entries) {
          if (combined == entry.key.replaceAll(' ', '').toLowerCase()) {
            return entry.value;
          }
        }
        return match.group(0)!;
      },
    );
    
    return result;
  }

  static String correctText(String rawText) {
    String corrected = correct(rawText);
    corrected = _fixCapitalization(corrected);
    corrected = _fixRepeatedSpaces(corrected);
    return corrected;
  }

  static String _fixCapitalization(String text) {
    return text.replaceAllMapped(
      RegExp(r'\.\s+([а-я])'),
      (match) => '. ${match.group(1)!.toUpperCase()}',
    );
  }

  static String _fixRepeatedSpaces(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
