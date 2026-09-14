import 'package:flutter_test/flutter_test.dart';
import 'package:dictapro/services/local_text_cleanup.dart';

void main() {
  group('LocalTextCleanup.cleanup — числительные в цифры', () {
    test('родительный падеж + целых/сотых + процент', () {
      expect(
        LocalTextCleanup.cleanup(
            'от восьмидесяти восьми целых шестидесяти четырёх сотых процента'),
        'от 88,64%',
      );
    });

    test('год порядковым числительным', () {
      expect(
        LocalTextCleanup.cleanup('две тысячи двадцать четвёртый год'),
        '2024 год',
      );
    });

    test('целых/сотых/процент (именительный падеж)', () {
      expect(
        LocalTextCleanup.cleanup(
            'восемьдесят восемь целых шестьдесят четыре сотых процента'),
        '88,64%',
      );
    });

    test('запятая + сотые без целой части', () {
      expect(
        LocalTextCleanup.cleanup('запятая шестьдесят четыре сотых'),
        ',64',
      );
    });

    test('запятая в середине фразы + процент', () {
      expect(
        LocalTextCleanup.cleanup(
            'сказал восемьдесят восемь запятая шестьдесят четыре процента'),
        'сказал 88,64%',
      );
    });

    test('дробь + единица измерения', () {
      expect(
        LocalTextCleanup.cleanup('двенадцать целых три десятых миллиграмма'),
        '12,3 мг',
      );
    });

    test('простое большое число', () {
      expect(LocalTextCleanup.cleanup('собрал двадцать пять коров'),
          'собрал 25 коров');
      expect(LocalTextCleanup.cleanup('цена триста рублей'), 'цена 300 рублей');
    });

    test('год с предложным падежом', () {
      expect(
        LocalTextCleanup.cleanup('в тысяча двести десятом году'),
        'в 1210 году',
      );
    });

    test('малые числа и обычный текст не трогаем', () {
      expect(LocalTextCleanup.cleanup('один из вариантов'), 'один из вариантов');
      expect(LocalTextCleanup.cleanup('пять грамм'), 'пять грамм');
    });
  });
}
