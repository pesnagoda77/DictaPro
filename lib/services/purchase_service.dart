// Task 054: разовая покупка «Полная версия» (non-consumable).
//
// Модель: бесплатно — до 15 минут расшифровки в день (см. UsageLimitService);
// покупка снимает лимит НАВСЕГДА. Подписок нет.
//
// Офлайн-требование (из ТЗ): после первого подтверждения покупка работает
// БЕЗ интернета. Поэтому права храним локально (SharedPreferences) и
// перепроверяем при запуске: если Store доступен — сверяемся с ним,
// если нет сети — доверяем локальному кэшу.
//
// Что создать в консолях (инструкция для владельца, см. журнал):
//   Play Console → Монетизация → Продукты → Одноразовые → id: full_unlock
//   App Store Connect → In-App Purchases → Non-Consumable → id: full_unlock
//   Цену подтвердить у владельца (ориентир: 990–1490 ₽ / 9,99–14,99 €).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PurchaseService {
  PurchaseService._();
  static final PurchaseService instance = PurchaseService._();

  /// Non-consumable «Полная версия». Должен совпадать с id товара в консолях.
  static const fullUnlockId = 'full_unlock';

  static const _kUnlocked = 'purchase_unlocked_v1';

  final _iap = InAppPurchase.instance;

  /// Права: true — полная версия. UI подписывается на поток.
  final ValueNotifier<bool> unlocked = ValueNotifier<bool>(false);

  StreamSubscription<List<PurchaseDetails>>? _sub;
  List<ProductDetails> _products = [];
  bool _storeAvailable = false;

  bool get storeAvailable => _storeAvailable;
  List<ProductDetails> get products => _products;

  Future<void> init() async {
    // 1) Локальный кэш — источник прав офлайн.
    final p = await SharedPreferences.getInstance();
    unlocked.value = p.getBool(_kUnlocked) ?? false;

    // 2) Поток покупок.
    _sub = _iap.purchaseStream.listen(_onPurchases);

    // 3) Перепроверка при запуске: без сети — остаёмся на кэше.
    try {
      _storeAvailable = await _iap.isAvailable();
      if (_storeAvailable) {
        final response = await _iap.queryProductDetails({fullUnlockId});
        _products = response.productDetails;
        if (response.notFoundIDs.contains(fullUnlockId)) {
          debugPrint('[purchase] товар $fullUnlockId не найден в консоли');
        }
        // Восстановление прошлых покупок (non-consumable живёт на аккаунте).
        await restore();
      }
    } catch (e) {
      debugPrint('[purchase] store недоступен ($e) — работаем на локальном кэше');
      _storeAvailable = false;
    }
  }

  /// Купить полную версию. Результат придёт в поток [_onPurchases].
  Future<bool> buyFullUnlock() async {
    final matches = _products.where((p) => p.id == fullUnlockId);
    if (matches.isEmpty) {
      debugPrint('[purchase] товар $fullUnlockId не загружен');
      return false;
    }
    final param = PurchaseParam(productDetails: matches.first);
    return _iap.buyNonConsumable(purchaseParam: param);
  }

  /// «Восстановить покупку» — после переустановки/на новом устройстве.
  Future<void> restore() async {
    try {
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint('[purchase] restore failed: $e');
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID != fullUnlockId) continue;
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _grantUnlock();
        case PurchaseStatus.pending:
          break; // ждём
        case PurchaseStatus.error:
          debugPrint('[purchase] error: ${purchase.error?.message}');
        case PurchaseStatus.canceled:
          break;
      }
      if (purchase.pendingCompletePurchase) {
        try {
          await _iap.completePurchase(purchase);
        } catch (e) {
          debugPrint('[purchase] completePurchase: $e');
        }
      }
    }
  }

  Future<void> _grantUnlock() async {
    unlocked.value = true;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kUnlocked, true);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
  }
}
