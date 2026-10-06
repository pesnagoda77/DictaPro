// Task 059: подписки и пакеты ИИ-часов для онлайн-итогов.
// Task 066: год в Google Play покупается как базовый план внутри подписки,
//           а не как отдельный товар (iOS: год — отдельный продукт, как раньше).
// Task 079: пакеты ИИ-часов — расходуемые (consumable) + строго одно
//           зачисление на один платёж:
//   • buyConsumable(autoConsume: false) — consume делаем сами после
//     зачисления часов, иначе повторная покупка пакета заблокирована
//     («У вас уже есть этот контент»), а restore перезачисляет часы;
//   • дедупликация по токену покупки (purchaseID) в prefs — красная
//     доставка того же платежа часов НЕ добавляет;
//   • приём «не того» типа покупок отключён: продукты вне каталога
//     (full_unlock / pack_* / sub_*) не применяются, только acknowledge;
//   • restore расходуемые не возвращает → баланс стабилен между запусками;
//   • дружелюпные тексты ошибок в [lastError] вместо сырых из магазина.
// iOS-ветка тот же Dart-код (StoreKit через in_app_purchase): consumable
// завершается completePurchase, логика идентична — отдельного фока нет.
// Task 083: жизненный цикл подписок — restore пересобирает набор, отменённые
//           подписки снимаются, офлайн-грейс 7 дней, разовые покупки не трогаем.
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
  // Task 079: токены уже зачисленных покупок пакетов (Set<String>) —
  // защита от перезачисления при redelivery/restore.
  static const _kAppliedPacks = 'applied_pack_tokens_v1';

  /// Task 083: время последней успешной проверки подписок (мс с эпохи).
  /// Офлайн-грейс: если store недоступен, держим текущий тариф не дольше
  /// [_graceDays] с этой даты, потом честно отключаем.
  static const _kLastVerifiedMs = 'subscription_last_verified_ms_v1';
  static const int _graceDays = 7;

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

  /// Task 079: последняя ошибка покупки человекочитаемым текстом
  /// (null — всё чисто). UI показывает вместе с общим «магазин недоступен».
  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);

  StreamSubscription<List<PurchaseDetails>>? _sub;
  List<ProductDetails> _products = [];
  bool _storeAvailable = false;

  /// 05.10 fix: во время restore копим ПОДТВЕРЖДЁННЫЕ магазином подписки,
  /// затем пересобираем набор с нуля — отменённые/истёкшие отпадают.
  bool _rebuild = false;
  final Set<String> _rebuildBuf = {};

  /// Task 083: true пока идёт restore-проверка (для индикатора в UI).
  final ValueNotifier<bool> restoring = ValueNotifier<bool>(false);

  bool get storeAvailable => _storeAvailable;
  List<ProductDetails> get products => _products;

  static const Map<SubscriptionTier, double> includedHours = {
    SubscriptionTier.diary: 10,
    SubscriptionTier.assistant: 20,
    SubscriptionTier.unlimited: 40,
  };

  /// Включённые часы РАСШИФРОВКИ в месяц по тарифам (логика холста V1):
  /// Дневник — 24 ч, Ассистент — 120 ч, Безлимит — без ограничений (null).
  static const Map<SubscriptionTier, int?> includedTranscriptionHours = {
    SubscriptionTier.diary: 24,
    SubscriptionTier.assistant: 120,
    SubscriptionTier.unlimited: null,
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
      // Task 083: store недоступен — проверяем грейс-период.
      await _applyOfflineGrace();
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

  /// Пакет часов (task 079): расходуемая покупка — часы зачисляются при
  /// доставке ровно один раз, затем purchase consume-ится. Повторная
  /// покупка того же пакета работает, restore баланс не раздувает.
  Future<bool> buyPack(String packId) => _buy(packId, consumable: true);

  String? priceOf(String productId) => _priceOf(productId);

  String? _priceOf(String productId) {
    for (final p in _products) {
      if (p.id == productId) return p.price;
    }
    return null;
  }

  Future<bool> _buy(String productId, {bool consumable = false}) async {
    final matches = _products.where((p) => p.id == productId);
    if (matches.isEmpty) {
      debugPrint('[purchase] товар $productId не загружен');
      lastError.value = 'Товар не найден в магазине. Попробуйте позже.';
      return false;
    }
    final param = PurchaseParam(productDetails: matches.first);
    try {
      if (consumable) {
        // Task 079: autoConsume: false — consume сами после зачисления
        // часов (см. _applyPack). С autoConsume магазин съедает покупку
        // до зачисления, а без consume повторная покупка невозможна.
        return await _iap.buyConsumable(
            purchaseParam: param, autoConsume: false);
      }
      // full_unlock и подписки — non-consumable: restore легитимно
      // возвращает их каждый запуск, обработка идемпотентна (task 066:
      // подписки на Android идут через buySubscription с offerToken).
      return await _iap.buyNonConsumable(purchaseParam: param);
    } catch (e) {
      debugPrint('[purchase] buy $productId failed: $e');
      lastError.value = _friendlyErrorText(e.toString());
      return false;
    }
  }

  /// Task 083: restore с индикатором и пересборкой набора подписок.
  /// Раньше только добавлял productId в локальный набор — отменённые
  /// подписки продолжали «гореть». Теперь собираем фактический набор
  /// из подтверждённых покупок.
  Future<void> restore() async {
    restoring.value = true;
    _rebuild = true;
    _rebuildBuf.clear();
    var verified = false;
    try {
      await _iap.restorePurchases();
      // restorePurchases() асинхронно шлёт события в purchaseStream.
      // Даём им время прийти (4 c), затем финализируем набор.
      await Future.delayed(const Duration(seconds: 4));
      verified = true;
    } catch (e) {
      debugPrint('[purchase] restore failed: $e');
    } finally {
      _rebuild = false;
      await _finalizeRestore(rebuild: verified);
      restoring.value = false;
    }
  }

  /// Task 083 + fix 05.10: после restore-задержки пересобираем набор активных
  /// подписок ИЗ ПОДТВЕРЖДЁННЫХ (_rebuildBuf). Если проверка не удалась —
  /// оставляем прежний набор (дальше решит офлайн-грейс).
  Future<void> _finalizeRestore({required bool rebuild}) async {
    final p = await SharedPreferences.getInstance();
    if (rebuild) {
      final rebuilt = _rebuildBuf.toList();
      await p.setStringList(_kActiveSubs, rebuilt);
      await p.setInt(_kLastVerifiedMs, DateTime.now().millisecondsSinceEpoch);
      tier.value = _tierFromProducts(rebuilt);
      debugPrint('[purchase] restore пересобрал набор: $rebuilt, tier=${tier.value}');
    } else {
      final active = p.getStringList(_kActiveSubs) ?? [];
      tier.value = _tierFromProducts(active);
      debugPrint('[purchase] restore не подтверждён — оставлен набор: $active');
    }
  }

  /// Task 083: офлайн-грейс. Если store недоступен — держим текущий тариф
  /// не дольше [_graceDays] с последней успешной проверки, потом снимаем.
  Future<void> _applyOfflineGrace() async {
    final p = await SharedPreferences.getInstance();
    final lastMs = p.getInt(_kLastVerifiedMs) ?? 0;
    if (lastMs == 0) return; // никогда не проверяли — не трогаем
    final elapsed = DateTime.now().millisecondsSinceEpoch - lastMs;
    if (elapsed > Duration(days: _graceDays).inMilliseconds) {
      // Грейс истёк — честно снимаем подписки.
      await p.setStringList(_kActiveSubs, []);
      tier.value = SubscriptionTier.none;
      debugPrint('[purchase] офлайн-грейс ${_graceDays}д истёк — подписки сняты');
    } else {
      debugPrint('[purchase] офлайн-грейс: ${elapsed ~/ Duration.millisecondsPerDay}д из $_graceDays — тариф держим');
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _applyPurchase(purchase);
        case PurchaseStatus.pending:
          break;
        case PurchaseStatus.error:
          lastError.value = _friendlyError(purchase.error);
          debugPrint('[purchase] error: ${purchase.error?.code} '
              '${purchase.error?.message}');
        case PurchaseStatus.canceled:
          lastError.value = 'Покупка отменена.';
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

  /// Task 079: приём только «своего» типа покупок. Продукты вне каталога
  /// (full_unlock / pack_* / sub_* и их *_year) не применяются — только
  /// acknowledge (completePurchase ниже), чтобы посторонняя/устаревшая
  /// доставка не меняла состояние приложения.
  Future<void> _applyPurchase(PurchaseDetails purchase) async {
    final productId = purchase.productID;
    if (productId == fullUnlockId) {
      await _grantUnlock();
      return;
    }
    if (packIds.containsKey(productId)) {
      await _applyPack(purchase);
      return;
    }
    final t = _tierOfProduct(productId);
    if (t != SubscriptionTier.none) {
      if (_rebuild) {
        // Идёт пересборка — копим подтверждённые подписки до финализации.
        _rebuildBuf.add(productId);
        return;
      }
      final p = await SharedPreferences.getInstance();
      final set = (p.getStringList(_kActiveSubs) ?? []).toSet()..add(productId);
      await p.setStringList(_kActiveSubs, set.toList());
      tier.value = _tierFromProducts(set.toList());
      return;
    }
    debugPrint('[purchase] неизвестный продукт $productId — приём отключён');
  }

  /// Task 079: зачислить пакет ровно один раз на один платёж.
  /// Дедупликация по токену покупки (purchaseID стабилен для транзакции;
  /// fallback — productID + transactionDate). Consume вызывает вызывающий
  /// код через completePurchase сразу после зачисления — при redelivery
  /// того же токена (сбой consume, перезапуск) часы не начисляются,
  /// магазин просто получает повторный completePurchase.
  Future<void> _applyPack(PurchaseDetails purchase) async {
    final productId = purchase.productID;
    final token = purchase.purchaseID ??
        '${purchase.productID}:${purchase.transactionDate}';
    final p = await SharedPreferences.getInstance();
    final applied = (p.getStringList(_kAppliedPacks) ?? []).toSet();
    if (applied.contains(token)) {
      debugPrint('[purchase] пакет $productId уже зачислен ($token) — skip');
      return;
    }
    await AiHoursService.instance.addPackHours(packIds[productId]!);
    applied.add(token);
    await p.setStringList(_kAppliedPacks, applied.toList());
    debugPrint('[purchase] пакет $productId зачислен: '
        '+${packIds[productId]} ч (токен $token)');
  }

  /// Дружелюбные тексты вместо сырых сообщений магазина (task 079).
  String _friendlyError(IAPError? error) =>
      _friendlyErrorText('${error?.code ?? ''} ${error?.message ?? ''}');

  String _friendlyErrorText(String raw) {
    final s = raw.toLowerCase();
    if (s.contains('already_owned') || s.contains('already owned')) {
      return 'Это уже куплено. Если покупка не отображается — '
          'нажмите «Восстановить покупки».';
    }
    if (s.contains('cancel')) return 'Покупка отменена.';
    if (s.contains('network') ||
        s.contains('unavailable') ||
        s.contains('service') ||
        s.contains('timeout')) {
      return 'Не удалось связаться с магазином. '
          'Проверьте интернет и попробуйте снова.';
    }
    return 'Ошибка покупки. Попробуйте позже.';
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

  /// Task 083: снять конкретный тариф (для будущего использования при
  /// server-side валидации subscriptionsv2 — задача 080 этап 2).
  Future<void> _deactivateTier(SubscriptionTier t) async {
    final subId = tierSubscriptionId[t];
    if (subId == null) return;
    final p = await SharedPreferences.getInstance();
    final set = (p.getStringList(_kActiveSubs) ?? []).toSet()..remove(subId);
    await p.setStringList(_kActiveSubs, set.toList());
    tier.value = _tierFromProducts(set.toList());
  }

  Future<void> dispose() async {
    await _sub?.cancel();
  }
}
