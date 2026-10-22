// Task 114: юнит-проверка ЕДИНОЙ формулы накопления срока кода
// (PurchaseService.computeCodeExpiry) на сценарии приёмки:
//   DIARY_MONTH → ASSISTANT_YEAR → UNLIMITED_YEAR.
// Ожидание (критерии приёмки Славана):
//   1) Дневник:  сейчас + 30 дней.
//   2) Ассистент: предыдущий конец + 1 год, тариф растёт.
//   3) Безлимит: + 1 год поверх накопленного.
import 'package:flutter_test/flutter_test.dart';
import 'package:dictapro/services/purchase_service.dart';

void main() {
  final now = DateTime(2026, 10, 22, 13, 0, 0);

  DateTime? end;
  const month = Duration(days: 30);
  const year = Duration(days: 365);

  test('DIARY_MONTH: сейчас + 30 дней', () {
    end = PurchaseService.computeCodeExpiry(
        now: now, currentEnd: null, yearly: false);
    expect(end, now.add(month));
  });

  test('ASSISTANT_YEAR: предыдущий конец + 1 год (остаток не теряется)', () {
    end = PurchaseService.computeCodeExpiry(
        now: now, currentEnd: end, yearly: true);
    expect(end, now.add(month).add(year));
  });

  test('UNLIMITED_YEAR: + 1 год поверх накопленного', () {
    end = PurchaseService.computeCodeExpiry(
        now: now, currentEnd: end, yearly: true);
    expect(end, now.add(month).add(year).add(year));
  });

  test('Просроченный текущий срок не тянет назад (base = сейчас)', () {
    final past = now.subtract(const Duration(days: 10));
    final e = PurchaseService.computeCodeExpiry(
        now: now, currentEnd: past, yearly: false);
    expect(e, now.add(month));
  });

  test('Тот же тариф месяц к месяцу накапливается (месяц+месяц = 2 месяца)', () {
    var e = PurchaseService.computeCodeExpiry(
        now: now, currentEnd: null, yearly: false);
    e = PurchaseService.computeCodeExpiry(
        now: now, currentEnd: e, yearly: false);
    expect(e, now.add(month + month));
  });

  group('addMonthsClamped (Task 115: цикл от дня активации)', () {
    test('обычный переход', () {
      expect(PurchaseService.addMonthsClamped(DateTime(2026, 10, 22), 1),
          DateTime(2026, 11, 22));
    });
    test('год через границу', () {
      expect(PurchaseService.addMonthsClamped(DateTime(2026, 12, 15), 1),
          DateTime(2027, 1, 15));
    });
    test('31 янв → 28 фев (не високосный)', () {
      expect(PurchaseService.addMonthsClamped(DateTime(2026, 1, 31), 1),
          DateTime(2026, 2, 28));
    });
    test('31 янв → 29 фев (високосный)', () {
      expect(PurchaseService.addMonthsClamped(DateTime(2028, 1, 31), 1),
          DateTime(2028, 2, 29));
    });
    test('31 мар → 30 апр (кламп 31→30)', () {
      expect(PurchaseService.addMonthsClamped(DateTime(2026, 3, 31), 1),
          DateTime(2026, 4, 30));
    });
  });
}
