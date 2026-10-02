// Обновлено 02.10.2026 (task 067): тест смоук-уровня без платформенных плагинов.
import 'package:flutter_test/flutter_test.dart';
import 'package:dictapro/app_strings.dart';

void main() {
  test('humanDuration форматирует время', () {
    expect(AppStrings.humanDuration(60000), contains('1'));
  });
}
