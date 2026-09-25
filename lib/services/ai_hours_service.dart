// Task 059: кошелёк ИИ-часов для онлайн-итогов.
//
// Две корзины:
//   1) Включённые часы подписки — месячные (ключ «YYYY-MM»), не переносятся.
//   2) Купленные пакеты — не сгорают, тратятся после включённых.
//
// Списание: объём = минуты аудио / 60, минимум 0.1 ч, округление вверх
// до 0.1 ч. Трактовка единицы «1 ИИ-час = 1 час аудиоматериала» —
// зафиксирована в ТЗ-обсуждении (модель эконом-класса, 29 ₽/час).
// Anti-rollback — тот же приём, что в UsageLimitService (054).
import 'package:shared_preferences/shared_preferences.dart';

import 'purchase_service.dart';

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

  /// Зачисление пакета (вызывается из PurchaseService при покупке).
  Future<void> addPackHours(double hours) async {
    final p = await SharedPreferences.getInstance();
    final cur = p.getDouble(_kPackMinutes) ?? 0;
    await p.setDouble(_kPackMinutes, cur + hours * 60.0);
  }

  /// Строка для UI: «осталось 12.5 ч (вкл. 10 + пакеты 2.5)».
  Future<String> balanceLabel() async {
    final incl = includedHours();
    final used = await includedUsedThisMonth();
    final pack = await packMinutesLeft();
    final inclLeft = (incl - used).clamp(0.0, double.infinity);
    final buf = StringBuffer();
    buf.write('ИИ-часы: осталось ${(inclLeft + pack / 60).toStringAsFixed(1)} ч');
    buf.write(' (по подписке ${inclLeft.toStringAsFixed(1)}, пакеты ${(pack / 60).toStringAsFixed(1)})');
    return buf.toString();
  }

  static double _chargeOf(int audioMs) {
    final hours = audioMs / 3600000.0;
    if (hours <= 0) return 0.1;
    return (hours * 10).ceilToDouble() / 10; // округление вверх до 0.1 ч
  }
}
