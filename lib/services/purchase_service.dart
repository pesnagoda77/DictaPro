// Task 059: подписки и пакеты ИИ-часов для онлайн-итогов.
//
// Модель (из ТЗ 059, цены/лимиты подтвердил Славан):
//   тарифы:      Дневник 10 ч/мес · Ассистент 20 ч/мес · Безлимит 40 ч/мес
//   пакеты сверх: 29 ₽/1 ч · 249 ₽/10 ч · 990 ₽/50 ч · 3 490 ₽/200 ч
//
// Продукты Store (создать в консолях, инструкция владельцу):
//   Подписки (auto-renewable): sub_diary, sub_assistant, sub_unlimited
//   Одноразовые (пакеты):      pack_1h, pack_10h, pack_50h, pack_200h
//
// Полная версия (054, full_unlock) снимает ДНЕВНОЙ ЛИМИТ РАСШИФРОВКИ —
// это отдельная ось. Онлайн-итоги живут на подписках/пакетах.
// Пакеты НЕ сгорают (механика «кошелька часов»); включённые часы — месячные.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_hours_service.dart';

enum SubscriptionTier { none, diary, assistant, unlimited }

class PurchaseService {
  PurchaseService._();
  static final PurchaseService instance = PurchaseService._();

  /// Non-consumable «Полная версия» (task 054).
  static const fullUnlockId = 'full_unlock';

  /// Task 059: подписки и пакеты часов.
  static const subDiaryId = 'sub_diary';
  static const subAssistantId = 'sub_assistant';
  static const subUnlimitedId = 'sub_unlimited';

  /// Task 065: годовые варианты тех же тарифов.
  /// iOS: год — отдельный продукт. Play: год — второй базовый план под тем же
  /// ID (дубль в запросе безвреден), цена берётся из оффера.
  static const subDiaryYearId = 'sub_diary_year';
  static const subAssistantYearId = 'sub_assistant_year';
  static const subUnlimitedYearId = 'sub_unlimited_year';

  static const packIds = {
    'pack_1h': 1.0,
    'pack_10h': 10.0,
    'pack_50h': 50.0,
    'pack_200h': 200.0,
  };

  static const _kUnlocked = 'purchase_unlocked_v1';
  static const _kActiveSubs = 'subscription_products_v1'; // Set<String>

  final _iap = InAppPurchase.instance;

  /// Полная версия (054): true — снят дневной лимит расшифровки.
  final ValueNotifier<bool> unlocked = ValueNotifier<bool>(false);

  /// Task 059: активный тариф подписки (максимальный из активных).
  final ValueNotifier<SubscriptionTier> tier =
      ValueNotifier<SubscriptionTier>(SubscriptionTier.none);

  StreamSubscription<List<PurchaseDetails>>? _sub;
  List<ProductDetails> _products = [];
  bool _storeAvailable = false;

  bool get storeAvailable => _storeAvailable;
  List<ProductDetails> get products => _products;

  static const Map<SubscriptionTier, double> includedHours = {
    SubscriptionTier.diary: 10,
    SubscriptionTier.assistant: 20,
    SubscriptionTier.unlimited: 40,
  };

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    unlocked.value = p.getBool(_kUnlocked) ?? false;
    tier.value = _tierFromProducts(p.getStringList(_kActiveSubs) ?? []);

    _sub = _iap.purchaseStream.listen(_onPurchases);

    try {
      _storeAvailable = await _iap.isAvailable();
      if (_storeAvailable) {
        final response = await _iap.queryProductDetails({
          fullUnlockId,
          subDiaryId,
          subAssistantId,
          subUnlimitedId,
          subDiaryYearId,
          subAssistantYearId,
          subUnlimitedYearId,
          ...packIds.keys,
        });
        _products = response.productDetails;
        final missing = response.notFoundIDs;
        if (missing.isNotEmpty) {
          debugPrint('[purchase] не найдены в консоли: $missing');
        }
        await restore();
      }
    } catch (e) {
      debugPrint('[purchase] store недоступен ($e) — работаем на локальном кэше');
      _storeAvailable = false;
    }
  }

  Future<bool> buyFullUnlock() async {
    return _buy(fullUnlockId);
  }

  Future<bool> buySubscription(SubscriptionTier t, {bool yearly = false}) {
    final id = switch (t) {
      SubscriptionTier.diary =>
        yearly ? subDiaryYearId : subDiaryId,
      SubscriptionTier.assistant =>
        yearly ? subAssistantYearId : subAssistantId,
      SubscriptionTier.unlimited =>
        yearly ? subUnlimitedYearId : subUnlimitedId,
      SubscriptionTier.none => '',
    };
    if (id.isEmpty) return Future.value(false);
    // Годовой ID может быть не создан в консоли — тогда честно падаем
    // на «товар не загружен», а не молча продаём месяц вместо года.
    return _buy(id);
  }

  /// Пакет часов (одноразовая покупка, часы падают в кошелёк).
  Future<bool> buyPack(String packId) => _buy(packId);

  Future<bool> _buy(String productId) async {
    final matches = _products.where((p) => p.id == productId);
    if (matches.isEmpty) {
      debugPrint('[purchase] товар $productId не загружен');
      return false;
    }
    final param = PurchaseParam(productDetails: matches.first);
    // Подписки и пакеты — одно и то же buyNonConsumable для
    // одноразовых; подписки идут через buyNonConsumable на обеих платформах
    // (auto-renewable приходит как подписка автоматически по типу товара).
    return _iap.buyNonConsumable(purchaseParam: param);
  }

  Future<void> restore() async {
    try {
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint('[purchase] restore failed: $e');
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _applyPurchase(purchase.productID);
        case PurchaseStatus.pending:
          break;
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

  Future<void> _applyPurchase(String productId) async {
    if (productId == fullUnlockId) {
      await _grantUnlock();
      return;
    }
    if (packIds.containsKey(productId)) {
      // Одноразовая покупка пакета: часы сразу в кошелёк. Повторная
      // доставка того же purchase не должна зачислить дважды — отсев
      // по transaction id оставляем Store (pendingCompletePurchase).
      await AiHoursService.instance.addPackHours(packIds[productId]!);
      return;
    }
    final t = _tierOfProduct(productId);
    if (t != SubscriptionTier.none) {
      final p = await SharedPreferences.getInstance();
      final set = (p.getStringList(_kActiveSubs) ?? []).toSet()..add(productId);
      await p.setStringList(_kActiveSubs, set.toList());
      tier.value = _tierFromProducts(set.toList());
    }
  }

  Future<void> _grantUnlock() async {
    unlocked.value = true;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kUnlocked, true);
  }

  SubscriptionTier _tierOfProduct(String productId) => switch (productId) {
        subDiaryId || subDiaryYearId => SubscriptionTier.diary,
        subAssistantId || subAssistantYearId => SubscriptionTier.assistant,
        subUnlimitedId || subUnlimitedYearId => SubscriptionTier.unlimited,
        _ => SubscriptionTier.none,
      };

  SubscriptionTier _tierFromProducts(List<String> products) {
    var best = SubscriptionTier.none;
    for (final p in products) {
      final t = _tierOfProduct(p);
      if (t.index > best.index) best = t;
    }
    return best;
  }

  Future<void> dispose() async {
    await _sub?.cancel();
  }
}
