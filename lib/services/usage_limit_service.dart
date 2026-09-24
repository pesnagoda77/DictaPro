// Task 054: дневной лимит бесплатной расшифровки.
//
// Модель (из ТЗ, цену/лимит подтвердил владелец):
//   бесплатно навсегда — 15 минут расшифровки в день + запись/хранение/экспорт
//   без ограничений; разовая покупка снимает лимит навсегда.
//
// Счётчик — локальный (SharedPreferences). Защита от сброса времени:
// храним дату последнего использования; если системные часы ПЕРЕВЕДЕНЫ
// назад раньше этой даты — считаем, что «сегодня» ещё не наступило,
// лимит не обнуляем.
import 'package:shared_preferences/shared_preferences.dart';

class UsageLimitService {
  UsageLimitService._();
  static final UsageLimitService instance = UsageLimitService._();

  /// Дневной лимит бесплатной расшифровки в минутах аудио.
  static const int dailyMinutesLimit = 15;

  static const _kDay = 'usage_day_v1'; // 'YYYY-MM-DD' последней траты
  static const _kMinutes = 'usage_minutes_v1'; // минут за _kDay
  static const _kLastSeen = 'usage_last_seen_ms_v1'; // anti-rollback

  static String _today() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  /// Сколько минут уже использовано сегодня.
  Future<int> usedMinutesToday() async {
    final p = await SharedPreferences.getInstance();
    final day = p.getString(_kDay);
    if (day != _today()) return 0;
    return p.getInt(_kMinutes) ?? 0;
  }

  /// Хватит ли лимита на расшифровку записи длиной [audioMs].
  /// Правило: разрешаем, если после этой записи не выйдем за лимит.
  Future<bool> canTranscribe(int audioMs) async {
    final used = await usedMinutesToday();
    final need = (audioMs / 60000).ceil();
    return used + need <= dailyMinutesLimit;
  }

  /// Фиксирует трату после успешной расшифровки.
  Future<void> recordUsage(int audioMs) async {
    final p = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final lastSeen = p.getInt(_kLastSeen) ?? 0;

    // Anti-rollback: часы перевели назад — «сегодня» не наступило,
    // продолжаем считать по старой дате (лимит не обнуляется).
    if (now.millisecondsSinceEpoch < lastSeen) {
      final day = p.getString(_kDay) ?? _today();
      final used = p.getInt(_kMinutes) ?? 0;
      final need = (audioMs / 60000).ceil();
      await p.setInt(_kMinutes, used + need);
      return; // _kLastSeen не трогаем — ждём реального наступления даты
    }

    final today = _today();
    final day = p.getString(_kDay);
    final used = day == today ? (p.getInt(_kMinutes) ?? 0) : 0;
    final need = (audioMs / 60000).ceil();
    await p.setString(_kDay, today);
    await p.setInt(_kMinutes, used + need);
    await p.setInt(_kLastSeen, now.millisecondsSinceEpoch);
  }

  /// Для paywall-диалога: «сегодня использовано X из Y минут».
  Future<String> todaySummary() async {
    final used = await usedMinutesToday();
    return '$used из $dailyMinutesLimit';
  }
}
