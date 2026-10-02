// Обновлено 02.10.2026 (task 067): Vosk удалён (task 019, движок — GigaAM).
// Оставлены простые проверки утилит, не требующие платформенных плагинов.
import 'package:flutter_test/flutter_test.dart';
import 'package:dictapro/app_strings.dart';

void main() {
  test('humanDuration: часы и минуты', () {
    expect(AppStrings.humanDuration(3600000), contains('1'));
    expect(AppStrings.humanDuration(90000), isNotEmpty);
  });
}
