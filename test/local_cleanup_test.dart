// Обновлено 02.10.2026 (task 067): LocalTextCleanup удалён вместе со старым
// пайплайном; оставлены простые проверки утилит.
import 'package:flutter_test/flutter_test.dart';
import 'package:dictapro/app_strings.dart';

void main() {
  test('humanDuration: базовые значения', () {
    expect(AppStrings.humanDuration(0), isNotEmpty);
    expect(AppStrings.humanDuration(1500), isNotEmpty);
  });
}
