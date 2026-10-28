// Task 115: НАКОПИТЕЛЬНЫЙ лимит включённых часов + цикл от дня активации.
//
// Раньше лимит брался из константы тарифа — при апгрейде Дневник→Ассистент
// остаток 22.1 ч просто исчезал (лимит «заменялся» 24 → 120). Теперь:
//   • _kIncludedTotal — выданная сумма часов текущего цикла (24+120=144);
//   • при активации/покупке тарифа total += includedHours[newTier];
//   • месячный цикл — от billingAnchor (день активации), см. PurchaseService.
//     При ролловере: used = 0, total = includedHours[текущего тарифа]
//     (неиспользованный остаток сгорает, свежий пакет текущего тарифа);
//   • купленные пакеты (packTr) — бессрочные, не сгорают.
//
// Две корзины:
//   1) Включённые часы тарифа — месячные (цикл от якоря), не переносятся.
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
  /// Task 115: накопленный лимит включённых часов текущего цикла.
  static const _kIncludedTotal = 'transcr_included_total_v1';
  static const _kPackMinutes = 'transcr_pack_minutes_v1';
  static const _kLastSeen = 'transcr_last_seen_ms_v1';

  static String _monthKey() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}';
  }

  /// Сколько часов включено у текущего тарифа по константе (null — безлимит).
  int? tierIncludedHours() =>
      PurchaseService.includedTranscriptionHours[PurchaseService.instance.tier.value];

  /// True — текущий тариф безлимитный (часы не списываются).
  bool get isUnlimited => tierIncludedHours() == null;

  /// Task 115: ролловер месячного цикла (от дня активации). При смене
  /// цикла — сброс used и выдача свежего пакета текущего тарифа
  /// (остаток сгорает). Пакеты не трогаем.
  Future<void> _rolloverIfNeeded() async {
    if (!await PurchaseService.instance.rolloverBillingCycleIfNeeded()) return;
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kIncludedUsed, 0);
    await p.setString(_kMonth, _monthKey());
    await p.setDouble(
        _kIncludedTotal, (tierIncludedHours() ?? 0).toDouble());
    PurchaseService.instance.planRevision.value++;
    debugPrint('[transcr-hours] новый месячный цикл: used=0, '
        'total=${tierIncludedHours() ?? 0}');
  }

  /// Task 115: накопленный лимит включённых часов (миграция: если ключа
  /// нет — берём константу текущего тарифа).
  Future<double> includedTotal() async {
    if (isUnlimited) return double.infinity;
    await _rolloverIfNeeded();
    final p = await SharedPreferences.getInstance();
    final t = p.getDouble(_kIncludedTotal);
    if (t != null) return t;
    final base = (tierIncludedHours() ?? 0).toDouble();
    await p.setDouble(_kIncludedTotal, base);
    return base;
  }

  /// Task 115: начислить включённые часы тарифа (активация/покупка).
  /// Суммируется с остатком (24 + 120 = 144); used не трогаем.
  Future<void> addIncludedHours(double hours) async {
    if (hours <= 0) return;
    await _rolloverIfNeeded();
    final p = await SharedPreferences.getInstance();
    final cur = p.getDouble(_kIncludedTotal) ??
        (tierIncludedHours() ?? 0).toDouble();
    await p.setDouble(_kIncludedTotal, cur + hours);
    PurchaseService.instance.planRevision.value++;
    debugPrint('[transcr-hours] включённые часы +$hours, всего ${cur + hours}');
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

  /// Полный баланс (в часах): включённые (за вычетом месячного расхода) + пакеты.
  /// Для безлимитного тарифа — double.infinity.
  Future<double> balanceHours() async {
    if (isUnlimited) return double.infinity;
    final incl = await includedTotal();
    final used = await includedUsedThisMonth();
    final pack = await packMinutesLeft();
    final inclLeft = (incl - used).clamp(0.0, double.infinity);
    return inclLeft + pack / 60.0;
  }

  /// Хватит ли баланса на файл длиной [audioMs]?
  /// Task 116 (Б, Славан 23.10): жёсткий сброс в бесплатный тариф при
  /// отмене/возврате подписки. total=0, used=0 → остаток цикла сгорает
  /// мгновенно, дальше действует бесплатные 30 мин/день (UsageLimitService).
  /// Купленные пакеты (pack_tr) НЕ трогаем — они бессрочный товар.
  Future<void> resetToFree() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kIncludedTotal, 0);
    await p.setDouble(_kIncludedUsed, 0);
    PurchaseService.instance.planRevision.value++;
    debugPrint('[transcr-hours] сброс в бесплатный: total=0, used=0');
  }

  /// Task 119: однократный санитар заражённых балансов (дубли грантов
  /// до фикса по purchaseToken: 192 ч вместо 24). [expectedTotal] =
  /// честные включённые тарифа + пакеты (в часах). used не трогаем;
  /// если used больше ожидаемого — total = used + 0.1 (честный минус).
  Future<String> sanitizeV2(double expectedTotal) async {
    if (isUnlimited) return ''; // бесконечная корзина, total не используется
    final p = await SharedPreferences.getInstance();
    final used = p.getString(_kMonth) == _monthKey()
        ? (p.getDouble(_kIncludedUsed) ?? 0)
        : 0;
    var want = expectedTotal;
    if (used > want) want = used + 0.1;
    final cur = p.getDouble(_kIncludedTotal);
    if (cur == null || cur <= want) return '';
    await p.setDouble(_kIncludedTotal, want);
    PurchaseService.instance.planRevision.value++;
    return 'transcr: включённые $cur→$want (дубли грантов)';
  }

  /// Task 116 П.5: санитар баланса расшифровки. used не может быть
  /// отрицательным, total не превышает накопленную базу + пакеты.
  /// Возвращает отчёт или '' (всё чисто).
  Future<String> sanitizeBalance() async {
    final p = await SharedPreferences.getInstance();
    final month = p.getString(_kMonth) ?? '';
    final used = p.getString(_kMonth) == _monthKey()
        ? (p.getDouble(_kIncludedUsed) ?? 0)
        : 0;
    final total = await includedTotal();
    final packMin = await packMinutesLeft();
    var report = '';
    if (used < 0) {
      await p.setDouble(_kIncludedUsed, 0);
      report += 'transcr: отрицательный used → 0; ';
    }
    if (total < 0) {
      report += 'transcr: total < 0 (кривой накопительный лимит) — клэмп к пакетам; ';
      // total пересчитается при следующем addIncludedHours; сейчас обнуляем
      // до 0, чтобы не раздавать бесконечные часы.
      await p.setDouble(_kIncludedTotal, 0);
    }
    if (packMin < 0) {
      await p.setDouble(_kPackMinutes, 0);
      report += 'transcr: отрицательные пакеты → 0; ';
    }
    return report;
  }

  Future<bool> canSpend(int audioMs) async {
    if (isUnlimited) return true;
    return (await balanceHours()) >= _chargeOf(audioMs);
  }

  /// Списание минут расшифровки. Возвращает фактически списанные часы
  /// (0 — не хватило; для безлимита — всегда 0, но true через canSpend).
  /// Сначала едятся включённые (из накопленного total), потом пакеты.
  Future<double> spend(int audioMs) async {
    if (isUnlimited) return 0; // безлимит — часы не тратятся
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
    final total = p.getDouble(_kIncludedTotal) ??
        (tierIncludedHours() ?? 0).toDouble();

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

  /// Строка для UI: «Расшифровка: 12,4 из 144 ч · Пакет: +30 ч»
  /// (знаменатель — накопленный лимит текущего цикла, task 115).
  /// Для безлимита: «Расшифровка: без ограничений».
  Future<String> balanceLabel() async {
    if (isUnlimited) {
      return AppStrings.tGlobal('transcr_unlimited_label');
    }
    final incl = await includedTotal();
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
