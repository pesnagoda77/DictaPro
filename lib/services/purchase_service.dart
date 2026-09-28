// Task 059: подписки и пакеты ИИ-часов для онлайн-итогов.
// Task 066: год в Google Play покупается как базовый план внутри подписки,
//           а не как отдельный товар (iOS: год — отдельный продукт, как раньше).
//
// Модель (из ТЗ 059, цены/лимиты подтвердил Славан):
//   тарифы:      Дневник 10 ч/мес · Ассистент 20 ч/мес · Безлимит 40 ч/мес
//   пакеты сверх: 29 ₽/1 ч · 249 ₽/10 ч · 990 ₽/50 ч · 3 490 ₽/200 ч
//
// Продукты Store:
//   Подписки: sub_diary, sub_assistant, sub_unlimited
//     · Play:   внутри каждой два базовых плана — monthly / yearly (task 066).
//     · App Store: месяц — sub_* , год — отдельный продукт sub_*_year (task 065).
//   Одноразовые (пакеты): pack_1h, pack_10h, pack_50h, pack_200h
//
// Полная версия (054, full_unlock) снимает ДНЕВНОЙ ЛИМИТ РАСШИФРОВКИ —
// это отдельная ось. Онлайн-итоги живут на подписках/пакетах.
// Пакеты НЕ сгорают (механика «кошелька часов»); включённые часы — месячные.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_hours_service.dart';

enum SubscriptionTier { none, diary, assistant, unlimited }

class PurchaseService {
  PurchaseService._();
  static final PurchaseService instance = PurchaseService._();

  /// Non-consumable «Полная версия» (task 054).
  static const fullUnlockId = 'full_unlock';

  /// Task 059/066: тариф → ID подписки (единый для Play и App Store).
  static const Map<SubscriptionTier, String> tierSubscriptionId = {
    SubscriptionTier.diary: 'sub_diary',
    SubscriptionTier.assistant: 'sub_assistant',
    SubscriptionTier.unlimited: 'sub_unlimited',
  };

  static const subDiaryId = 'sub_diary';
  static const subAssistantId = 'sub_assistant';
  static const subUnlimitedId = 'sub_unlimited';

  /// Task 066: базовые планы Google Play (подтверждено скриншотом консоли
  /// 27.09.2026): месяц — 'monthly', год — 'annual'. ID планов для всех
  /// трёх подписок одинаковые. Менять только здесь.
  static const monthlyBasePlanId = 'monthly';
  static const yearlyBasePlanId = 'annual';

  /// Task 065: годовые варианты — только App Store (отдельные продукты).
  /// На Android эти ID не существуют и в запрос не включаются (task 066).
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

  /// Task 066 п.5: Play не сообщает basePlanId в покупке — период, выбранный
  /// пользователем, запоминаем локально. Точная дата продления — только
  /// серверной проверкой (Play Developer API) — отдельная задача.
  static const _kPeriodPrefix = 'subscription_period_v1_'; // + subId

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
        // Task 066: год на Android — базовый план внутри подписки, отдельных
        // товаров *_year в Play нет; запрашивать их не нужно.
        final ids = <String>{
          fullUnlockId,
          ...tierSubscriptionId.values,
          if (!Platform.isAndroid) ...[
            subDiaryYearId,
            subAssistantYearId,
            subUnlimitedYearId,
          ],
          ...packIds.keys,
        };
        final response = await _iap.queryProductDetails(ids);
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

  /// Покупка подписки. iOS: год — отдельный продукт. Android: выбирается
  /// базовый план (monthly/yearly) внутри подписки sub_* (task 066).
  Future<bool> buySubscription(SubscriptionTier t,
      {bool yearly = false}) async {
    final subId = tierSubscriptionId[t];
    if (subId == null) return false;

    if (!Platform.isAndroid) {
      final id = yearly ? '${subId}_year' : subId;
      return _buy(id);
    }

    final planId = yearly ? yearlyBasePlanId : monthlyBasePlanId;
    for (final p in _products.where((p) => p.id == subId)) {
      if (p is! GooglePlayProductDetails) continue;
      final idx = p.subscriptionIndex;
      final offers = p.productDetails.subscriptionOfferDetails;
      if (idx == null || offers == null || idx >= offers.length) continue;
      if (offers[idx].basePlanId != planId) continue;
      await _rememberPeriod(subId, yearly);
      return _iap.buyNonConsumable(
        purchaseParam: GooglePlayPurchaseParam(
          productDetails: p,
          offerToken: p.offerToken,
        ),
      );
    }
    debugPrint('[purchase] базовый план $planId не найден в $subId');
    return false;
  }

  /// Task 066: цена подписки для витрины. Android — из оффера выбранного
  /// базового плана (на одну подписку приходит по ProductDetails на план).
  String? priceOfSubscription(SubscriptionTier t,
      {required bool yearly}) {
    final subId = tierSubscriptionId[t];
    if (subId == null) return null;
    if (!Platform.isAndroid) {
      return _priceOf(yearly ? '${subId}_year' : subId);
    }
    final planId = yearly ? yearlyBasePlanId : monthlyBasePlanId;
    for (final p in _products.where((p) => p.id == subId)) {
      if (p is! GooglePlayProductDetails) continue;
      final idx = p.subscriptionIndex;
      final offers = p.productDetails.subscriptionOfferDetails;
      if (idx == null || offers == null || idx >= offers.length) continue;
      if (offers[idx].basePlanId == planId) return p.price;
    }
    return null;
  }

  /// Локально запомненный период подписки ('monthly'/'yearly').
  /// null — период неизвестен (restore без покупки в этой сессии).
  Future<String?> periodOf(SubscriptionTier t) async {
    final subId = tierSubscriptionId[t];
    if (subId == null) return null;
    final p = await SharedPreferences.getInstance();
    return p.getString('$_kPeriodPrefix$subId');
  }

  /// Пакет часов (одноразовая покупка, часы падают в кошелёк).
  Future<bool> buyPack(String packId) => _buy(packId);

  String? priceOf(String productId) => _priceOf(productId);

  String? _priceOf(String productId) {
    for (final p in _products) {
      if (p.id == productId) return p.price;
    }
    return null;
  }

  Future<bool> _buy(String productId) async {
    final matches = _products.where((p) => p.id == productId);
    if (matches.isEmpty) {
      debugPrint('[purchase] товар $productId не загружен');
      return false;
    }
    final param = PurchaseParam(productDetails: matches.first);
    // full_unlock и пакеты — одноразовые покупки; подписки проходят через
    // buySubscription() (task 066: на Android с offerToken базового плана).
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

  Future<void> _rememberPeriod(String subId, bool yearly) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        '$_kPeriodPrefix$subId', yearly ? yearlyBasePlanId : monthlyBasePlanId);
  }

  /// Task 066: тариф определяется по productId покупки. На Android год и
  /// месяц приходят с одним ID (sub_diary) — период берём из локальной
  /// записи (periodOf), сделанной в момент покупки.
  SubscriptionTier _tierOfProduct(String productId) {
    for (final e in tierSubscriptionId.entries) {
      if (productId == e.value || productId == '${e.value}_year') {
        return e.key;
      }
    }
    return SubscriptionTier.none;
  }

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
