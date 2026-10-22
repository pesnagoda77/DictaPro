// Task 110: кошелёк часов расшифровки (по образцу AiHoursService).
//
// Две корзины:
//   1) Включённые часы тарифа — месячные (ключ «YYYY-MM»), не переносятся.
//   2) Купленные пакеты — не сгорают, тратятся после включённых.
//
// Списание: сначала включённые, затем пакет; при безлимитном тарифе
// часов не списываются (вернёт 0 из charge — но транзакция идёт).
// Anti-rollback системных часов сохранён (тот же приём, что в UsageLimitService).
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'purchase_service.dart';
import '../app_strings.dart';

class TranscriptionHoursService {
  TranscriptionHoursService._();
  static final TranscriptionHoursService instance = TranscriptionHoursService._();

  static const _kMonth = 'transcr_month_v1';
  static const _kIncludedUsed = 'transcr_included_used_v1';
  static const _kPackMinutes = 'transcr_pack_minutes_v1';
  static const _kLastSeen = 'transcr_last_seen_ms_v1';

  static String _monthKey() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}';
  }

  /// Сколько часов включено у текущего тарифа (null — безлимит).
  int? includedHours() =>
      PurchaseService.includedTranscriptionHours[PurchaseService.instance.tier.value];

  /// True — текущий тариф безлимитный (часы не списываются).
  bool get isUnlimited => includedHours() == null;

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
  /// Для безлимитного тарифа — double.infinity.
  Future<double> balanceHours() async {
    if (isUnlimited) return double.infinity;
    final incl = includedHours()!.toDouble();
    final used = await includedUsedThisMonth();
    final pack = await packMinutesLeft();
    final inclLeft = (incl - used).clamp(0.0, double.infinity);
    return inclLeft + pack / 60.0;
  }

  /// Хватит ли баланса на файл длиной [audioMs]?
  Future<bool> canSpend(int audioMs) async {
    if (isUnlimited) return true;
    return (await balanceHours()) >= _chargeOf(audioMs);
  }

  /// Списание минут расшифровки. Возвращает фактически списанные часы
  /// (0 — не хватило; для безлимита — всегда 0, но true через canSpend).
  /// Сначала едятся включённые (месячные), потом пакеты.
  Future<double> spend(int audioMs) async {
    if (isUnlimited) return 0; // безлимит — часы не тратятся
    final need = _chargeOf(audioMs);
    final p = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final lastSeen = p.getInt(_kLastSeen) ?? 0;
    final month = p.getString(_kMonth) ?? _monthKey();
    final monthOk = month == _monthKey() &&
        now.millisecondsSinceEpoch >= lastSeen; // anti-rollback
    final used = monthOk ? (p.getDouble(_kIncludedUsed) ?? 0.0) : 0.0;
    final packMin = p.getDouble(_kPackMinutes) ?? 0;

    double inclLeft = (includedHours()!.toDouble() - used).clamp(0.0, double.infinity).toDouble();
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
    PurchaseService.instance.planRevision.value++;
    return need;
  }

  /// Зачисление пакета часов расшифровки (вызывается из PurchaseService).
  Future<void> addPackHours(double hours) async {
    final p = await SharedPreferences.getInstance();
    final cur = p.getDouble(_kPackMinutes) ?? 0;
    await p.setDouble(_kPackMinutes, cur + hours * 60.0);
  }

  /// Возврат пакета: списываем минимум(текущий пакетный баланс, объём пакета).
  Future<void> revokePackHours(double hours) async {
    final p = await SharedPreferences.getInstance();
    final cur = p.getDouble(_kPackMinutes) ?? 0;
    final revokeMin = hours * 60.0;
    final newVal = (cur - revokeMin).clamp(0.0, double.infinity);
    await p.setDouble(_kPackMinutes, newVal);
    debugPrint('[transcr-hours] возврат пакета: списано $hours ч, остаток ${newVal / 60} ч');
  }

  /// Строка для UI: «Расшифровка: 12,4 из 24 ч · Пакет: +30 ч»
  /// Для безлимита: «Расшифровка: без ограничений».
  Future<String> balanceLabel() async {
    if (isUnlimited) {
      return AppStrings.tGlobal('transcr_unlimited_label');
    }
    final incl = includedHours()!.toDouble();
    final used = await includedUsedThisMonth();
    final pack = await packMinutesLeft();
    final buf = StringBuffer();
    buf.write(AppStrings.tfGlobal('transcr_balance_label', {
      'u': used.toStringAsFixed(1),
      'n': incl.toStringAsFixed(0),
    }));
    if (pack > 0) {
      buf.write(AppStrings.tfGlobal('transcr_pack_label', {
        'h': (pack / 60).toStringAsFixed(1),
      }));
    }
    return buf.toString();
  }

  static double _chargeOf(int audioMs) {
    final hours = audioMs / 3600000.0;
    if (hours <= 0) return 0.1;
    return (hours * 10).ceilToDouble() / 10; // округление вверх до 0.1 ч
  }
}
