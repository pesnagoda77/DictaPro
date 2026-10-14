// Task 105: серверные сессии — замена общего x-app-key на короткоживущие
// токены. Контракт: docs/integration_102_session_api.md (task 102, сервер
// готов и протестирован).
//
// Flow:
//   1. При старте приложения — POST /session (installId + покупки + коды)
//      → получаем Bearer-токен (TTL 12 ч) + баланс часов.
//   2. Онлайн-итоги ходят с Authorization: Bearer <token>.
//   3. При 401 — обновляем токен, повторяем запрос один раз.
//   4. balanceMs из ответа /session и /summarize — обновляем локально.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'billing_verify_service.dart';

/// Результат запроса сессии.
class SessionResult {
  final bool ok;
  final String? token;
  final int ttlSec;
  final String plan;
  final int? subUntilMs;
  final double includedHours;
  final double packsHours;
  final int balanceMs;
  final String? error;

  const SessionResult({
    required this.ok,
    this.token,
    this.ttlSec = 43200,
    this.plan = 'none',
    this.subUntilMs,
    this.includedHours = 0,
    this.packsHours = 0,
    this.balanceMs = 0,
    this.error,
  });
}

/// Сервис серверной сессии: токен, баланс, авто-обновление.
class SessionService {
  SessionService._();
  static final SessionService instance = SessionService._();

  /// URL billing-api (тот же worker, что и для /verify).
  static const _billingUrl =
      String.fromEnvironment('BILLING_API_URL', defaultValue: '');

  static const _kInstallId = 'session_install_id_v1';
  static const _kToken = 'session_token_v1';
  static const _kTokenExpiryMs = 'session_token_expiry_ms_v1';
  static const _kBalanceMs = 'session_balance_ms_v1';
  static const _kServerPlan = 'session_plan_v1';
  static const _kActivatedCodes = 'session_activated_codes_v1';

  /// Текущий токен (null — не получен или истёк).
  String? _token;
  DateTime? _tokenExpiry;
  int _balanceMs = 0;

  /// Колбэк при обновлении баланса с сервера.
  void Function(int balanceMs)? onBalanceUpdate;

  String? get token => _token;
  bool get hasValidToken =>
      _token != null &&
      _tokenExpiry != null &&
      DateTime.now().isBefore(_tokenExpiry!);

  /// Баланс в миллисекундах (серверный).
  int get balanceMs => _balanceMs;
  double get balanceHours => _balanceMs / 3600000.0;

  /// Инициализация: загружаем сохранённый токен/баланс, запрашиваем новый.
  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    _token = p.getString(_kToken);
    final expMs = p.getInt(_kTokenExpiryMs);
    _tokenExpiry = expMs != null
        ? DateTime.fromMillisecondsSinceEpoch(expMs)
        : null;
    _balanceMs = p.getInt(_kBalanceMs) ?? 0;

    // Токен истёк или скоро истечёт (< 1 ч) — обновляем при старте.
    if (!hasValidToken ||
        _tokenExpiry!.difference(DateTime.now()).inHours < 1) {
      await refreshSession();
    }
  }

  /// Получить (или обновить) серверную сессию.
  /// Отправляет installId + покупки + активированные коды.
  Future<SessionResult> refreshSession() async {
    if (_billingUrl.isEmpty) {
      debugPrint('[session] BILLING_API_URL не задан — сессия недоступна');
      return const SessionResult(ok: false, error: 'no_url');
    }

    final installId = await _getOrCreateInstallId();
    final purchases = await _collectPurchases();
    final codes = await getActivatedCodes();

    try {
      final resp = await http
          .post(
            Uri.parse('$_billingUrl/session'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'installId': installId,
              'package': 'com.dictapro.app',
              'purchases': purchases,
              'codes': codes,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode != 200) {
        debugPrint('[session] HTTP ${resp.statusCode}');
        return SessionResult(ok: false, error: 'http_${resp.statusCode}');
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        final err = data['error'] as String? ?? 'unknown';
        debugPrint('[session] сервер вернул ошибку: $err');
        return SessionResult(ok: false, error: err);
      }

      _token = data['token'] as String?;
      _tokenExpiry = DateTime.now().add(
        Duration(seconds: (data['ttlSec'] as int?) ?? 43200),
      );
      _balanceMs = (data['balanceMs'] as num?)?.toInt() ?? 0;

      // Сохраняем
      final p = await SharedPreferences.getInstance();
      await p.setString(_kToken, _token ?? '');
      await p.setInt(
          _kTokenExpiryMs, _tokenExpiry!.millisecondsSinceEpoch);
      await p.setInt(_kBalanceMs, _balanceMs);
      await p.setString(_kServerPlan, data['plan'] as String? ?? 'none');

      onBalanceUpdate?.call(_balanceMs);

      debugPrint('[session] токен получен, баланс: '
          '${(_balanceMs / 3600000).toStringAsFixed(1)} ч');

      return SessionResult(
        ok: true,
        token: _token,
        ttlSec: (data['ttlSec'] as int?) ?? 43200,
        plan: data['plan'] as String? ?? 'none',
        subUntilMs: (data['subUntilMs'] as num?)?.toInt(),
        includedHours:
            ((data['includedHours'] as num?) ?? 0).toDouble(),
        packsHours: ((data['packsHours'] as num?) ?? 0).toDouble(),
        balanceMs: _balanceMs,
      );
    } on TimeoutException {
      debugPrint('[session] timeout');
      return const SessionResult(ok: false, error: 'timeout');
    } catch (e) {
      debugPrint('[session] ошибка: $e');
      return SessionResult(ok: false, error: e.toString());
    }
  }

  /// Получить токен для запроса. Если токен истёк — обновляет.
  /// Возвращает null если получить не удалось.
  Future<String?> ensureToken() async {
    if (hasValidToken) return _token;
    final r = await refreshSession();
    return r.ok ? r.token : null;
  }

  /// Обновить баланс из ответа /summarize.
  void updateBalanceFromSummary(int balanceMs) {
    _balanceMs = balanceMs;
    SharedPreferences.getInstance().then((p) {
      p.setInt(_kBalanceMs, balanceMs);
    });
    onBalanceUpdate?.call(balanceMs);
  }

  /// Добавить активированный код в локальный список.
  Future<void> addActivatedCode(String code) async {
    final p = await SharedPreferences.getInstance();
    final codes = (p.getStringList(_kActivatedCodes) ?? []).toSet();
    codes.add(code);
    await p.setStringList(_kActivatedCodes, codes.toList());
    // После добавления кода — обновляем сессию (сервер начислит часы).
    await refreshSession();
  }

  /// Список активированных кодов.
  Future<List<String>> getActivatedCodes() async {
    final p = await SharedPreferences.getInstance();
    return p.getStringList(_kActivatedCodes) ?? [];
  }

  /// Стабильный ID установки (UUID, генерируется один раз).
  Future<String> _getOrCreateInstallId() async {
    final p = await SharedPreferences.getInstance();
    var id = p.getString(_kInstallId);
    if (id == null || id.isEmpty) {
      id = _generateUuid();
      await p.setString(_kInstallId, id);
      debugPrint('[session] новый installId: $id');
    }
    return id;
  }

  /// Собрать покупки для /session.
  Future<List<Map<String, String>>> _collectPurchases() async {
    final p = await SharedPreferences.getInstance();
    final activeSubs = p.getStringList('subscription_products_v1') ?? [];
    final result = <Map<String, String>>[];

    // Подписки: нужен purchaseToken — берём из BillingVerifyService
    final tokens = BillingVerifyService.instance.pendingTokens;
    for (final subId in activeSubs) {
      final token = tokens[subId];
      if (token != null && token.isNotEmpty) {
        result.add({'productId': subId, 'purchaseToken': token});
      }
    }
    return result;
  }

  /// Простой UUID v4.
  static String _generateUuid() {
    final rnd = DateTime.now().millisecondsSinceEpoch;
    final hex = rnd.toRadixString(16).padLeft(12, '0');
    final hex2 = (rnd * 7 + 13).toRadixString(16).padLeft(12, '0');
    return 'xxxxxxxx-xxxx-4xxx-yxxx-$hex$hex2'
        .replaceAllMapped(RegExp('[xy]'), (match) {
      final r = (rnd + match.start * 17) & 0xf;
      final c = match.group(0)![0];
      return (c == 'x' ? r : (r & 0x3 | 0x8)).toRadixString(16);
    });
  }
}
