// Task 087 (часть Б): серверная валидация покупок через Cloudflare Worker.
//
// Контракт с воркером (часть А — Краб):
//   POST /verify {package, productId, purchaseToken}
//   → {status: active|canceled_active|expired|refunded|unknown, expiryTime, kind: sub|pack}
//
// Поведение:
//   - При запуске, при открытии «Подписки», не чаще 1 раза в N часов.
//   - Ответ сервера — истина: refunded/expired → снять права немедленно.
//   - Офлайн-грейс 7 дней — только при недоступности сервера (честных не наказываем).
//   - При сетевых ошибках права не снимать.
//   - Пакеты: пометка зачисления на сервере (одноразово), при возврате — списать неиспользованное.
//
// Запреты: не логировать purchaseToken/персональные данные; секреты не в код.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_hours_service.dart';
import 'purchase_service.dart';

/// Результат серверной проверки покупки.
enum VerifyStatus { active, canceledActive, expired, refunded, unknown }

/// Серверная сверка покупок. Вызывается из PurchaseService.
class BillingVerifyService {
  BillingVerifyService._();
  static final BillingVerifyService instance = BillingVerifyService._();

  /// Task 090: боевой URL воркера (task 087 часть А — Краб).
  /// Был: String? workerUrl — теперь константа.
  static const String? _workerUrl =
      String.fromEnvironment('BILLING_API_URL', defaultValue: '');

  String? get workerUrl {
    final url = _workerUrl;
    if (url == null || url.isEmpty) return null;
    return url;
  }

  /// Минимальный интервал между сверками (часы).
  static const int _verifyIntervalHours = 24;

  /// Офлайн-грейс при недоступности сервера (дни).
  static const int _offlineGraceDays = 7;

  static const _kLastVerifyMs = 'billing_verify_last_ms_v1';
  static const _kPendingTokens = 'billing_verify_pending_v1'; // Map<String, String>

  /// Покупки, ожидающие серверной пометки зачисления (productId → purchaseToken).
  final Map<String, String> _pendingAck = {};

  /// Инициализация: загружаем сохранённые purchaseToken для будущей сверки.
  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    final pending = p.getStringList(_kPendingTokens) ?? [];
    for (final entry in pending) {
      final idx = entry.indexOf(':');
      if (idx > 0) {
        _pendingAck[entry.substring(0, idx)] = entry.substring(idx + 1);
      }
    }
  }

  /// Сохранить purchaseToken для последующей серверной сверки.
  /// Вызывается из PurchaseService при подтверждении покупки.
  Future<void> recordPurchaseToken(String productId, String purchaseToken) async {
    _pendingAck[productId] = purchaseToken;
    await _savePending();
  }

  /// Нужна ли серверная сверка (по интервалу).
  Future<bool> needsVerify() async {
    final p = await SharedPreferences.getInstance();
    final lastMs = p.getInt(_kLastVerifyMs) ?? 0;
    if (lastMs == 0) return true;
    final elapsed = DateTime.now().millisecondsSinceEpoch - lastMs;
    return elapsed > Duration(hours: _verifyIntervalHours).inMilliseconds;
  }

  /// Выполнить серверную сверку всех сохранённых покупок.
  /// Вызывается при запуске и при открытии «Подписки».
  Future<void> verifyAll() async {
    if (workerUrl == null) {
      debugPrint('[billing-verify] worker URL не задан — сверка пропущена');
      return;
    }

    final need = await needsVerify();
    if (!need) {
      debugPrint('[billing-verify] сверка недавно выполнялась — пропуск');
      return;
    }

    final p = await SharedPreferences.getInstance();
    final tokens = Map<String, String>.from(_pendingAck);

    var anySuccess = false;
    for (final entry in tokens.entries) {
      final result = await _verifyOne(entry.key, entry.value);
      if (result == null) continue; // сетевая ошибка — не снимаем права
      anySuccess = true;
      await _applyServerResult(entry.key, result);
    }

    if (anySuccess) {
      await p.setInt(_kLastVerifyMs, DateTime.now().millisecondsSinceEpoch);
    }
  }

  /// Проверить одну покупку на сервере.
  /// Возвращает null при сетевой ошибке (не снимаем права).
  Future<VerifyResult?> _verifyOne(String productId, String purchaseToken) async {
    try {
      final response = await http.post(
        Uri.parse('$workerUrl/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'package': 'com.dictapro.app',
          'productId': productId,
          'purchaseToken': purchaseToken,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint('[billing-verify] HTTP ${response.statusCode} для $productId');
        return null; // серверная ошибка — не снимаем права
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final statusStr = data['status'] as String? ?? 'unknown';
      final expiryMs = data['expiryTime'] as int?;
      final kind = data['kind'] as String? ?? 'sub';

      final status = switch (statusStr) {
        'active' => VerifyStatus.active,
        'canceled_active' => VerifyStatus.canceledActive,
        'expired' => VerifyStatus.expired,
        'refunded' => VerifyStatus.refunded,
        _ => VerifyStatus.unknown,
      };

      return VerifyResult(
        status: status,
        expiryTime: expiryMs != null ? DateTime.fromMillisecondsSinceEpoch(expiryMs) : null,
        isSubscription: kind == 'sub',
      );
    } on TimeoutException {
      debugPrint('[billing-verify] timeout для $productId');
      return null;
    } on SocketException {
      debugPrint('[billing-verify] нет сети для $productId');
      return null;
    } catch (e) {
      debugPrint('[billing-verify] ошибка для $productId: $e');
      return null;
    }
  }

  /// Применить результат серверной проверки.
  Future<void> _applyServerResult(String productId, VerifyResult result) async {
    switch (result.status) {
      case VerifyStatus.refunded:
      case VerifyStatus.expired:
        // Сервер подтвердил: возврат или истечение — снимаем права.
        await _revokeProduct(productId);
        _pendingAck.remove(productId);
        await _savePending();
        debugPrint('[billing-verify] $productId: права сняты (${result.status})');

      case VerifyStatus.canceledActive:
        // Отменена, но период ещё активен — держим права до expiryTime.
        // Дальше Play сам перестанет продлевать, сверка снимет.
        break;

      case VerifyStatus.active:
        // Активна — всё ок, ничего не делаем.
        break;

      case VerifyStatus.unknown:
        // Неизвестный статус — не трогаем.
        break;
    }
  }

  /// Снять права для продукта (подписка или пакет).
  Future<void> _revokeProduct(String productId) async {
    final purchase = PurchaseService.instance;

    // Подписка?
    final tier = _tierOfProduct(productId);
    if (tier != SubscriptionTier.none) {
      await purchase.deactivateTierForVerify(tier);
      return;
    }

    // Пакет? Списать неиспользованное из кошелька.
    final packHours = PurchaseService.packIds[productId];
    if (packHours != null) {
      await AiHoursService.instance.revokePackHours(packHours);
    }
  }

  SubscriptionTier _tierOfProduct(String productId) {
    for (final e in PurchaseService.tierSubscriptionId.entries) {
      if (productId == e.value || productId == '${e.value}_year') {
        return e.key;
      }
    }
    return SubscriptionTier.none;
  }

  Future<void> _savePending() async {
    final p = await SharedPreferences.getInstance();
    final list = _pendingAck.entries.map((e) => '${e.key}:${e.value}').toList();
    await p.setStringList(_kPendingTokens, list);
  }

  /// Task 090: URL больше не устанавливается вручную — берётся из
  /// --dart-define=BILLING_API_URL. Метод оставлен для совместимости (no-op).
  void setWorkerUrl(String url) {}
}

class VerifyResult {
  final VerifyStatus status;
  final DateTime? expiryTime;
  final bool isSubscription;

  VerifyResult({
    required this.status,
    required this.expiryTime,
    required this.isSubscription,
  });
}
