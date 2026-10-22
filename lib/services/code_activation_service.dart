// Task 089: активация кодов (персональных и промо) через единый модуль
// activation_codes. Типы кодов: DIARY_MONTH, DIARY_YEAR, ASSISTANT_MONTH,
// ASSISTANT_YEAR, UNLIMITED_MONTH, UNLIMITED_YEAR, PACK_1H, PACK_10H,
// PACK_50H, PACK_200H.
// Task 104: переход на Ed25519. В приложении — только публичный ключ;
// CODE_KEY (HMAC) больше не нужен. v1-коды без ключа → needsOnline →
// серверная активация через /session.
import 'package:activation_codes/activation_codes.dart' as ac;
import 'package:flutter/foundation.dart';

import 'ai_hours_service.dart';
import 'purchase_service.dart';
import 'session_service.dart';

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

  /// URL сервера для промо-кодов и v1-фолбэка (task 087/104).
  static const _serverUrl = String.fromEnvironment('BILLING_API_URL', defaultValue: '');

  late final ac.CodeBackend _backend;
  bool _ready = false;

  /// Task 104: инициализация без CODE_KEY. Ed25519-публичный ключ вшит
  /// в модуль. v1-коды без HMAC-ключа возвращают needsOnline — клиент
  /// направляет их на сервер через SessionService.
  Future<void> init() async {
    final local = ac.LocalCodeBackend(
      appId: _appId,
      appCode: _appCode,
      types: _types,
      // key: не передаём — v1 офлайн недоступен без HMAC, v2 через Ed25519
    );

    if (_serverUrl.isNotEmpty) {
      final server = ac.ServerCodeBackend(baseUrl: _serverUrl, appId: _appId);
      _backend = ac.SmartCodeBackend(local: local, server: server, appId: _appId);
    } else {
      _backend = local;
    }
    _ready = true;
    debugPrint('[CodeActivation] initialized (Ed25519, no CODE_KEY)');
  }

  /// Всегда true — v2 коды проверяются офлайн, v1 через сервер.
  bool get isReady => _ready;

  /// Активировать код. Возвращает результат.
  /// v2 — офлайн (Ed25519). v1 — needsOnline если нет HMAC-ключа.
  Future<ac.CodeResult> redeem(String code) async {
    if (!_ready) {
      return const ac.CodeResult(ok: false, error: ac.CodeError.server);
    }
    return _backend.redeem(code);
  }

  /// Task 104: v1-код без HMAC-ключа → needsOnline.
  /// Серверная активация через /session (codes): сервер проверяет подпись
  /// и начисляет план/часы; возвращаем результат в формате модуля.
  Future<ac.CodeResult> redeemOnline(String code) async {
    final o = await SessionService.instance.activateCodeOnServer(code);
    if (o == null) {
      return const ac.CodeResult(ok: false, error: ac.CodeError.network);
    }
    DateTime? exp;
    if (o.expiresAtMs != null) {
      exp = DateTime.fromMillisecondsSinceEpoch(o.expiresAtMs!, isUtc: true);
    }
    if (o.applied || o.already) {
      return ac.CodeResult(
        ok: true,
        alreadyUsed: o.already,
        typeKey: o.typeKey,
        expiresAt: exp,
      );
    }
    final err = (o.error ?? '').toLowerCase();
    if (err.contains('expired')) {
      return const ac.CodeResult(ok: false, error: ac.CodeError.expired);
    }
    if (err.contains('bad_sig')) {
      return const ac.CodeResult(ok: false, error: ac.CodeError.badSignature);
    }
    return const ac.CodeResult(ok: false, error: ac.CodeError.server);
  }

  /// Применить результат активации: выдать тариф или пакет.
  /// [rawCode] — исходный введённый код (для серверной синхронизации).
  Future<void> applyCodeResult(ac.CodeResult result, {String? rawCode}) async {
    if (!result.ok) return;
    final typeKey = result.typeKey;
    if (typeKey == null) return;

    // Сохраняем код для серверной сессии (task 105)
    if (rawCode != null && rawCode.isNotEmpty) {
      await SessionService.instance.addActivatedCode(rawCode);
    }

    // Тариф?
    final tier = tierOfTypeKey(typeKey);
    if (tier != SubscriptionTier.none) {
      // Task 114: вся логика (срок с накоплением, запись tier/expiry,
      // бонусные ИИ-часы с дедупликацией по коду) — в PurchaseService.
      await PurchaseService.instance.activateCode(
        codeTier: tier,
        typeKey: typeKey,
        rawCode: rawCode ?? '',
        payloadExpiresAt: result.expiresAt,
      );
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
}
