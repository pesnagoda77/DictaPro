// Task 089: активация кодов (персональных и промо) через единый модуль
// activation_codes. Типы кодов: DIARY_MONTH, DIARY_YEAR, ASSISTANT_MONTH,
// ASSISTANT_YEAR, UNLIMITED_MONTH, UNLIMITED_YEAR, PACK_1H, PACK_10H,
// PACK_50H, PACK_200H. Офлайн-коды (DICTA-...) проверяются локально,
// промо-коды (читаемые строки) — через сервер.
import 'package:activation_codes/activation_codes.dart' as ac;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_hours_service.dart';
import 'purchase_service.dart';

/// Сервис активации кодов для Дикты.
class CodeActivationService {
  CodeActivationService._();
  static final CodeActivationService instance = CodeActivationService._();

  // Коды приложения: typeKey → (typeCode для payload, appCode)
  static const _appId = 'DICTA';
  static const _appCode = 2; // уникальный код приложения в payload

  /// Типы: typeKey → typeCode (байт в payload).
  /// Совпадают с генератором Краба (tools/gen_codes.py).
  static const Map<String, int> _types = {
    'DIARY_MONTH': 1,
    'DIARY_YEAR': 2,
    'ASSISTANT_MONTH': 3,
    'ASSISTANT_YEAR': 4,
    'UNLIMITED_MONTH': 5,
    'UNLIMITED_YEAR': 6,
    'PACK_1H': 10,
    'PACK_10H': 11,
    'PACK_50H': 12,
    'PACK_200H': 13,
  };

  /// Ключ HMAC из --dart-define=CODE_KEY.
  static const _key = String.fromEnvironment('CODE_KEY', defaultValue: '');

  /// URL сервера для промо-кодов (из Краба, task 087).
  static const _serverUrl = String.fromEnvironment('BILLING_API_URL', defaultValue: '');

  late final ac.CodeBackend _backend;

  Future<void> init() async {
    if (_key.isEmpty) {
      debugPrint('[CodeActivation] CODE_KEY not set — codes disabled');
      return;
    }

    final local = ac.LocalCodeBackend(
      appId: _appId,
      appCode: _appCode,
      types: _types,
      key: _key,
    );

    if (_serverUrl.isNotEmpty) {
      final server = ac.ServerCodeBackend(baseUrl: _serverUrl, appId: _appId);
      _backend = ac.SmartCodeBackend(local: local, server: server, appId: _appId);
    } else {
      _backend = local;
    }
  }

  bool get isReady => _key.isNotEmpty;

  /// Активировать код. Возвращает результат.
  Future<ac.CodeResult> redeem(String code) async {
    if (_key.isEmpty) {
      return const ac.CodeResult(ok: false, error: ac.CodeError.badSignature);
    }
    return _backend.redeem(code);
  }

  /// Применить результат активации: выдать тариф или пакет.
  Future<void> applyCodeResult(ac.CodeResult result) async {
    if (!result.ok) return;
    final typeKey = result.typeKey;
    if (typeKey == null) return;

    // Тариф?
    final tier = tierOfTypeKey(typeKey);
    if (tier != SubscriptionTier.none) {
      await _grantTierFromCode(tier, result.expiresAt);
      return;
    }

    // Пакет?
    final packHours = packOfTypeKey(typeKey);
    if (packHours != null) {
      await AiHoursService.instance.addPackHours(packHours);
      return;
    }
  }

  /// typeKey → тариф (публично, для UI).
  SubscriptionTier tierOfTypeKey(String typeKey) {
    return switch (typeKey) {
      'DIARY_MONTH' || 'DIARY_YEAR' => SubscriptionTier.diary,
      'ASSISTANT_MONTH' || 'ASSISTANT_YEAR' => SubscriptionTier.assistant,
      'UNLIMITED_MONTH' || 'UNLIMITED_YEAR' => SubscriptionTier.unlimited,
      _ => SubscriptionTier.none,
    };
  }

  /// typeKey → часы пакета (публично, для UI).
  double? packOfTypeKey(String typeKey) {
    return switch (typeKey) {
      'PACK_1H' => 1.0,
      'PACK_10H' => 10.0,
      'PACK_50H' => 50.0,
      'PACK_200H' => 200.0,
      _ => null,
    };
  }

  /// Выдать тариф по коду: объединяем с Play-подпиской (берём максимум).
  Future<void> _grantTierFromCode(SubscriptionTier codeTier, DateTime? expiresAt) async {
    final purchase = PurchaseService.instance;
    final currentTier = purchase.tier.value;

    // Берём максимальный тариф из текущего и кода
    final maxTier = _maxTier(currentTier, codeTier);

    // Если код даёт более высокий тариф — устанавливаем
    if (_tierRank(maxTier) > _tierRank(currentTier)) {
      await purchase.setTierFromCode(maxTier, expiresAt);
    }
  }

  int _tierRank(SubscriptionTier t) => switch (t) {
        SubscriptionTier.none => 0,
        SubscriptionTier.diary => 1,
        SubscriptionTier.assistant => 2,
        SubscriptionTier.unlimited => 3,
      };

  SubscriptionTier _maxTier(SubscriptionTier a, SubscriptionTier b) =>
      _tierRank(a) >= _tierRank(b) ? a : b;
}
