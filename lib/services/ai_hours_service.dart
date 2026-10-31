// Task 115: НАКОПИТЕЛЬНЫЙ месячный бонус + цикл от дня активации.
//
// Бонусные ИИ-часы тарифа (Дневник 10 / Ассистент 20 / Безлимит 40) сгорают
// в конце месячного цикла, но ПРИ АПГРЕЙДЕ суммируются с остатком:
// было 10 (Дневник) → активирован Ассистент (+20) → баланс 30 (не 20).
// Реализация: _kIncludedTotal — выданная сумма бонусов текущего цикла,
// addMonthlyBonus делает total += hours. Месячный цикл считается от дня
// активации (billingAnchor в PurchaseService), а не от 1-го числа; при
// ролловере used = 0, total = бонус текущего тарифа (остаток сгорает).
// Купленные ПАКЕТЫ (за деньги) — бессрочные, не сгорают.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'purchase_service.dart';
import '../app_strings.dart';

class AiHoursService {
  AiHoursService._();
  static final AiHoursService instance = AiHoursService._();

  static const _kMonth = 'aihours_month_v1';
  static const _kIncludedUsed = 'aihours_included_used_v1';
  /// Task 115: накопленный месячный бонус текущего цикла.
  static const _kIncludedTotal = 'aihours_included_total_v1';
  static const _kPackMinutes = 'aihours_pack_minutes_v1';
  static const _kLastSeen = 'aihours_last_seen_ms_v1';
  /// Task 116 П.5: журнал начислений месячного бонуса
  /// ('<cycleStartMs>:<hours>') — основа санитара балансов.
  static const _kBonusLedger = 'aihours_bonus_ledger_v1';

  static String _monthKey() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}';
  }

  /// Сколько часов включено у текущего тарифа по константе (0 — без подписки).
  double tierIncludedHours() =>
      PurchaseService.includedHours[PurchaseService.instance.tier.value] ?? 0;

  /// Task 115: ролловер месячного цикла (от дня активации). При смене
  /// цикла — сброс used и свежий бонус текущего тарифа (остаток сгорает).
  Future<void> _rolloverIfNeeded() async {
    if (!await PurchaseService.instance.rolloverBillingCycleIfNeeded()) return;
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kIncludedUsed, 0);
    await p.setString(_kMonth, _monthKey());
    await p.setDouble(_kIncludedTotal, tierIncludedHours());
    PurchaseService.instance.bump('ai-hours');
    debugPrint('[ai-hours] новый месячный цикл: used=0, '
        'bonus=${tierIncludedHours()}');
  }

  /// Задача 120 (Славан): месячный бонус ВЫЧИСЛЯЕТСЯ из тарифа
  /// (не хранится счётчиком — дубли грантов невозможны архитектурно).
  Future<double> includedTotal() async {
    await _rolloverIfNeeded();
    return tierIncludedHours();
  }

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

  /// Task 119: однократный санитар заражённых балансов (дубли грантов
  /// до фикса по purchaseToken: 50 ИИ-ч вместо 10). [expectedIncluded] —
  /// честный месячный бонус текущего тарифа; пакеты — отдельная
  /// бессрочная корзина, их НЕ трогаем. Возвращает (отчёт, был ли
  /// вообще бонус) — PurchaseService по этому флагу сидит кулдаун,
  /// чтобы токен-грант после обновления не насыпал второй бонус.
  Future<(String, bool)> sanitizeV2(double expectedIncluded) async {
    final p = await SharedPreferences.getInstance();
    final used = p.getString(_kMonth) == _monthKey()
        ? (p.getDouble(_kIncludedUsed) ?? 0)
        : 0;
    var want = expectedIncluded;
    if (used > want) want = used + 0.1; // честный минус, не обнуляем расход
    final cur = p.getDouble(_kIncludedTotal);
    final hadBonus = (cur ?? 0) > 0;
    if (cur == null || cur <= want) return ('', hadBonus);
    await p.setDouble(_kIncludedTotal, want);
    PurchaseService.instance.bump('ai-hours');
    return ('ai_hours: включённые $cur→$want (дубли грантов)', hadBonus);
  }

  /// Task 116 П.5: санитар баланса. Месячная часть (включённые тарифа)
  /// не может превышать includedHours(tier). Пакеты не трогаем — они
  /// бессрочные и приходят отдельно. Возвращает отчёт или '' (всё чисто).
  Future<String> sanitizeBalance() async {
    final p = await SharedPreferences.getInstance();
    final base = tierIncludedHours();
    final used = p.getString(_kMonth) == _monthKey()
        ? (p.getDouble(_kIncludedUsed) ?? 0)
        : 0;
    final inclLeft = (base - used).clamp(0.0, double.infinity);
    if (base <= 0 && inclLeft <= 0) return ''; // без тарифа лечить нечем
    if (used < 0) {
      await p.setDouble(_kIncludedUsed, 0);
      return 'ai_hours: отрицательный used → 0';
    }
    return ''; // месячная корзина сама ограничена base − used
  }

  /// Полный баланс (в часах): включённые (за вычетом месячного расхода) + пакеты.
  Future<double> balanceHours() async {
    final incl = await includedTotal();
    final used = await includedUsedThisMonth();
    final pack = await packMinutesLeft();
    final inclLeft = (incl - used).clamp(0.0, double.infinity);
    return inclLeft + pack / 60.0;
  }

  /// Хватит ли баланса на файл длиной [audioMs]?
  Future<bool> canSpend(int audioMs) async =>
      (await balanceHours()) >= _chargeOf(audioMs);

  /// Списание. Возвращает фактически списанные часы (0 — не хватило).
  /// Сначала едятся включённые (из накопленного total), потом пакеты.
  Future<double> spend(int audioMs) async {
    final need = _chargeOf(audioMs);
    final p = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await _rolloverIfNeeded(); // Task 115: цикл от дня активации
    final lastSeen = p.getInt(_kLastSeen) ?? 0;
    final month = p.getString(_kMonth) ?? _monthKey();
    final monthOk = month == _monthKey() &&
        now.millisecondsSinceEpoch >= lastSeen; // anti-rollback
    final used = monthOk ? (p.getDouble(_kIncludedUsed) ?? 0.0) : 0.0;
    final packMin = p.getDouble(_kPackMinutes) ?? 0;
    final total = await includedTotal();

    double inclLeft = (total - used).clamp(0.0, double.infinity).toDouble();
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
    // Task 115: шапка обновляется сразу после траты (без пересоздания).
    PurchaseService.instance.bump('ai-hours');
    return need;
  }

  /// Зачисление купленного пакета (бессрочный — не сгорает).
  /// Вызывается из PurchaseService при покупке пакета за деньги.
  Future<void> addPackHours(double hours) async {
    final p = await SharedPreferences.getInstance();
    final cur = p.getDouble(_kPackMinutes) ?? 0;
    await p.setDouble(_kPackMinutes, cur + hours * 60.0);
  }

  /// Задача 120 (Славан): начисление БОНУСНЫХ ИИ-часов счётчиком УДАЛЕНО.
  /// Месячный бонус = тариф (замена, не сложение): «Ассистент» даёт ровно
  /// 20 ИИ-ч в месяц, апгрейд с Дневника не даёт +10 сверху.
  Future<void> addMonthlyBonus(double hours) async {
    if (hours <= 0) return;
    await _rolloverIfNeeded();
    // Если тарифный бонус уже выставлен ролловером/другим грантом —
    // ничего не делаем (замена семантика).
    final cur = await includedTotal();
    if (cur >= hours) {
      debugPrint('[ai-hours] бонус уже выставлен ($cur ≥ $hours) — skip');
      return;
    }
    debugPrint('[ai-hours] бонус $hours уже учтён вычисляемой моделью');
    PurchaseService.instance.bump('ai-hours');
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
    final incl = await includedTotal();
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
