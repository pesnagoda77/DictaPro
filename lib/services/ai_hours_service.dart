// Task 114 (доп. Славан 22.10): бонусные ИИ-часы тарифа должны СГОРАТЬ
// в конце месяца, как и часы расшифровки. Раньше addPackHours клал их
// в «пакетную» корзину (не сгорает) — это неверно для бонуса тарифа.
//
// Решение: добавляем отдельный метод addMonthlyBonus(hours) — кладёт в
// МЕСЯЧНУЮ корзину через уменьшение списанного: includedUsed -= hours
// (клэмп до 0). Месячная корзина обнуляется сама при смене месяца
// (ключ YYYY-MM) — значит, бонус сгорит 1-го числа следующего месяца.
// Купленные ПАКЕТЫ (продаваемые за деньги) остаются бессрочными.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'purchase_service.dart';
import '../app_strings.dart';

class AiHoursService {
  AiHoursService._();
  static final AiHoursService instance = AiHoursService._();

  static const _kMonth = 'aihours_month_v1';
  static const _kIncludedUsed = 'aihours_included_used_v1';
  static const _kPackMinutes = 'aihours_pack_minutes_v1';
  static const _kLastSeen = 'aihours_last_seen_ms_v1';

  static String _monthKey() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}';
  }

  /// Сколько часов включено у текущего тарифа (0 — без подписки).
  double includedHours() =>
      PurchaseService.includedHours[PurchaseService.instance.tier.value] ?? 0;

  /// Сколько минут осталось из пакетов.
  Future<double> packMinutesLeft() async {
    final p = await SharedPreferences.getInstance();
    return p.getDouble(_kPackMinutes) ?? 0;
  }

  /// Использовано включённых часов в этом месяце.
  Future<double> includedUsedThisMonth() async {
    final p = await SharedPreferences.getInstance();
    if (p.getString(_kMonth) != _monthKey()) return 0;
    return p.getDouble(_kIncludedUsed) ?? 0;
  }

  /// Полный баланс (в часах): включённые (за вычетом месячного расхода) + пакеты.
  Future<double> balanceHours() async {
    final incl = includedHours();
    final used = await includedUsedThisMonth();
    final pack = await packMinutesLeft();
    final inclLeft = (incl - used).clamp(0.0, double.infinity);
    return inclLeft + pack / 60.0;
  }

  /// Хватит ли баланса на файл длиной [audioMs]?
  Future<bool> canSpend(int audioMs) async =>
      (await balanceHours()) >= _chargeOf(audioMs);

  /// Списание. Возвращает фактически списанные часы (0 — не хватило).
  /// Сначала едятся включённые (месячные), потом пакеты.
  Future<double> spend(int audioMs) async {
    final need = _chargeOf(audioMs);
    final p = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final lastSeen = p.getInt(_kLastSeen) ?? 0;
    final month = p.getString(_kMonth) ?? _monthKey();
    final monthOk = month == _monthKey() &&
        now.millisecondsSinceEpoch >= lastSeen; // anti-rollback
    final used = monthOk ? (p.getDouble(_kIncludedUsed) ?? 0.0) : 0.0;
    final packMin = p.getDouble(_kPackMinutes) ?? 0;

    double inclLeft = (includedHours() - used).clamp(0.0, double.infinity).toDouble();
    var needHours = need;

    double usedNew = used;
    var packNew = packMin;
    if (inclLeft >= needHours) {
      usedNew += needHours;
      needHours = 0;
    } else {
      needHours -= inclLeft;
      usedNew += inclLeft;
      final needMin = needHours * 60.0;
      if (packMin >= needMin) {
        packNew = packMin - needMin;
        needHours = 0;
      } else {
        return 0; // не хватило
      }
    }

    await p.setString(_kMonth, _monthKey());
    await p.setDouble(_kIncludedUsed, usedNew);
    await p.setDouble(_kPackMinutes, packNew);
    await p.setInt(_kLastSeen, now.millisecondsSinceEpoch);
    return need;
  }

  /// Зачисление купленного пакета (бессрочный — не сгорает).
  /// Вызывается из PurchaseService при покупке пакета за деньги.
  Future<void> addPackHours(double hours) async {
    final p = await SharedPreferences.getInstance();
    final cur = p.getDouble(_kPackMinutes) ?? 0;
    await p.setDouble(_kPackMinutes, cur + hours * 60.0);
  }

  /// Task 114 (Славан 22.10): начисление БОНУСНЫХ ИИ-часов тарифа
  /// (Дневник 10 / Ассистент 20 / Безлимит 40 за месяц подписки).
  /// Кладём в МЕСЯЧНУЮ корзину (сгорают в конце месяца), а не в пакетную.
  /// Реализация: уменьшаем includedUsed (т.е. «возвращаем» неиспользованное
  /// из месячной квоты), с клэмпом в 0. Корзина привязана к ключу YYYY-MM —
  /// 1-го числа следующего месяца бонус естественно сгорает.
  Future<void> addMonthlyBonus(double hours) async {
    final p = await SharedPreferences.getInstance();
    if (p.getString(_kMonth) != _monthKey()) {
      await p.setString(_kMonth, _monthKey());
      await p.setDouble(_kIncludedUsed, 0);
    }
    final used = p.getDouble(_kIncludedUsed) ?? 0;
    final newVal = (used - hours).clamp(0.0, double.infinity);
    await p.setDouble(_kIncludedUsed, newVal);
    debugPrint('[ai-hours] месячный бонус +$hours ч (сгорит в конце месяца)');
  }

  /// Task 087: списать неиспользованные часы пакета при возврате.
  Future<void> revokePackHours(double hours) async {
    final p = await SharedPreferences.getInstance();
    final cur = p.getDouble(_kPackMinutes) ?? 0;
    final revokeMin = hours * 60.0;
    final newVal = (cur - revokeMin).clamp(0.0, double.infinity);
    await p.setDouble(_kPackMinutes, newVal);
    debugPrint('[ai-hours] возврат пакета: списано $hours ч, остаток ${newVal / 60} ч');
  }

  /// Строка для UI: «осталось 12.5 ч (вкл. 10 + пакеты 2.5)».
  Future<String> balanceLabel() async {
    final incl = includedHours();
    final used = await includedUsedThisMonth();
    final pack = await packMinutesLeft();
    final inclLeft = (incl - used).clamp(0.0, double.infinity);
    final buf = StringBuffer();
    buf.write(AppStrings.tfGlobal('ai_hours_left', {'h': (inclLeft + pack / 60).toStringAsFixed(1)}));
    buf.write(AppStrings.tfGlobal('ai_hours_breakdown', {'a': inclLeft.toStringAsFixed(1), 'p': (pack / 60).toStringAsFixed(1)}));
    return buf.toString();
  }

  static double _chargeOf(int audioMs) {
    final hours = audioMs / 3600000.0;
    if (hours <= 0) return 0.1;
    return (hours * 10).ceilToDouble() / 10; // округление вверх до 0.1 ч
  }
}
