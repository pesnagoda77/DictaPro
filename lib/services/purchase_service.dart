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
// Task 114: ЕДИНАЯ ЛОГИКА ТАРИФОВ И ЧАСОВ. Один источник правды — этот
//           сервис. Код активации больше НЕ пишет tier/expiry сам —
//           только через [activateCode]. ИИ-часы начисляются там же,
//           один раз на каждый код (дедуп по 'code:<rawCode>'). Накопление:
//           новый срок = max(текущий конец, сейчас) + период кода —
//           и для того же тарифа, и для другого (остаток не теряется).
//           payload-дата кода больше не используется как абсолютный срок
//           доступа (в кодах это «код действует до», а не «доступ до» —
//           из-за неё сроки дублировались и год превращался в 60 дней).
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
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_hours_service.dart';
import 'billing_verify_service.dart';
import 'transcription_hours_service.dart';

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

  /// Task 110: пакеты часов РАСШИФРОВКИ (consumable, по аналогии с packIds).
  /// Ценовая сетка утверждена Славаном 18.10.2026.
  static const packTrIds = {
    'pack_tr_10h': 10.0,
    'pack_tr_30h': 30.0,
    'pack_tr_100h': 100.0,
    'pack_tr_200h': 200.0,
  };

  static const _kUnlocked = 'purchase_unlocked_v1';
  static const _kActiveSubs = 'subscription_products_v1'; // Set<String>
  static const _kCodeTier = 'code_activated_tier_v1';
  static const _kCodeExpiry = 'code_activated_expiry_v1';
  /// Task 114: период последнего активированного кода ('monthly'/'yearly').
  static const _kCodePeriod = 'code_activated_period_v1';
static const _kPlayExpiry = 'play_subscription_expiry_v1'; // Task 110: expiryTimeMillis активной Play-подписки
static const _kSubBonusApplied = 'sub_bonus_applied_v1'; // 20.10: токены, по которым бонус ИИ-часов уже начислен
  /// Task 119: кулдаун ИИ-бонуса тарифа против схемы «купил-отменил-купил».
  /// Ключ = '$_kAiBonusLastPrefix' + tier.name, значение — мс последнего
  /// начисления. Месячные тиры: 20 дней, годовые: 320. Отмена подписки
  /// кулдаун НЕ сбрасывает — это и есть защита.
  static const _kAiBonusLastPrefix = 'ai_bonus_last_ms_';
  static const int aiBonusCooldownDays = 20;
  static const int aiBonusCooldownDaysYearly = 320;
  /// Task 119: однократная миграция-санитар заражённых балансов
  /// (дубли грантов до фикса по токену).
  static const _kBalancesSanitizedV2 = 'balances_sanitized_v2';
  // Task 079: токены уже зачисленных покупок пакетов (Set<String>) —
  // защита от перезачисления при redelivery/restore.
  static const _kAppliedPacks = 'applied_pack_tokens_v1';

  /// Task 083: время последней успешной проверки подписок (мс с эпохи).
  /// Офлайн-грейс: если store недоступен, держим текущий тариф не дольше
  /// [_graceDays] с этой даты, потом честно отключаем.
  static const _kLastVerifiedMs = 'subscription_last_verified_ms_v1';
  static const int _graceDays = 3;

  /// Task 115: месячный цикл включённых часов считается от ДНЯ АКТИВАЦИИ
  /// тарифа (покупки/кода), а не от 1-го числа. Храним дату начала
  /// текущего цикла; ролловер — см. [rolloverBillingCycleIfNeeded].
  static const _kBillingCycleStartMs = 'billing_cycle_start_ms_v1';

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

  /// Task 114: счётчик изменений плана (тариф/срок/активация кода).
  /// UI подписывается и перечитывает шапку БЕЗ входа-выхода со страницы.
  final ValueNotifier<int> planRevision = ValueNotifier<int>(0);

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

  /// Task 116 П.6: завершённость полного init (включая restore).
  /// UI (ИИ-итоги) ждёт [ready] перед проверкой баланса — иначе гонка
  /// «0.0 часов» с первого тапа.
  final Completer<void> _ready = Completer<void>();
  Future<void> get ready => _ready.future;

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    unlocked.value = p.getBool(_kUnlocked) ?? false;
    await _applyEffectiveTier();

    _sub = _iap.purchaseStream.listen(_onPurchases);

    try {
      _storeAvailable = await _iap.isAvailable();
      if (_storeAvailable) {
        // Task 066: год на Android — базовый план внутри подписки, отдельных
        // товаров *_year в Play нет; запрашивать их не нужно.
        await refreshProducts();
        // Task 087: инициализация серверной сверки (worker URL получим от Краба).
      await BillingVerifyService.instance.init();
      // При запуске — сверка если нужна.
      await BillingVerifyService.instance.verifyAll();
      await restore();
      // Task 116 П.5: санитар балансов после старта — лечит устройства,
      // уже накопившие лишние бонусы (2210 ч у тестера BY).
      // Task 119: санитар v2 — клэмп к честной формуле (тариф + пакеты)
      // заражённых дублями грантов устройств (тестер DE: 192 ч / 50 ИИ-ч).
      lastSanitizeReport = [
        await _runBalanceSanity(),
        await _runSanitizeV2(),
      ].where((e) => e.isNotEmpty).join('\n');
      }
    } catch (e) {
      debugPrint('[purchase] store недоступен ($e) — работаем на локальном кэше');
      _storeAvailable = false;
      // Task 083: store недоступен — проверяем грейс-период.
      await _applyOfflineGrace();
    } finally {
      // Task 116: init завершён (успешно или кэш-режим) — выпускаем ждущих.
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  /// Task 116: последний отчёт санитара балансов ('' — всё чисто).
  /// Экрана диагностики в приложении нет (убран в task 109) — отчёт
  /// читается из логов и этого поля.
  String lastSanitizeReport = '';

  /// Task 116 П.5: санитар балансов. Ожидаемый месячный лимит = база
  /// текущего тарифа + бонусы, записанные в журнале текущего цикла.
  /// Фактический баланс больше — следы бага 2210 ч → клэмп + отчёт.
  /// Запускается после старта — уже заражённые устройства лечатся.
  Future<String> _runBalanceSanity() async {
    final ai = await AiHoursService.instance.sanitizeBalance();
    final tr = await TranscriptionHoursService.instance.sanitizeBalance();
    final report = [ai, tr].where((e) => e.isNotEmpty).join('\n');
    if (report.isNotEmpty) {
      debugPrint('[purchase] SANITY:\n$report');
    }
    return report;
  }

  /// Task 119: однократная миграция-санитар заражённых балансов (дубли
  /// грантов до фикса по токену). Часы: total = включённые тарифа +
  /// купленные пакеты. ИИ: включённые = бонус тарифа (пакеты — отдельная
  /// бессрочная корзина). Факт больше ожидаемого — клэмп + отчёт.
  /// Кулдаун ИИ-бонуса сидим, если бонус уже выдавался: иначе первый же
  /// токен-грант после обновления насыпал бы второй бонус сверху.
  Future<String> _runSanitizeV2() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_kBalancesSanitizedV2) == true) return '';
    final t = tier.value;
    final trReport = await TranscriptionHoursService.instance.sanitizeV2(
      t == SubscriptionTier.none
          ? 0.0
          : ((includedTranscriptionHours[t] ?? 0) +
              (await TranscriptionHoursService.instance.packMinutesLeft()) /
                  60.0),
    );
    final (aiReport, aiHadBonus) = await AiHoursService.instance
        .sanitizeV2((includedHours[t] ?? 0).toDouble());
    if (t != SubscriptionTier.none && aiHadBonus) {
      await _markAiBonusGranted(t);
    }
    await p.setBool(_kBalancesSanitizedV2, true);
    final report = [trReport, aiReport].where((e) => e.isNotEmpty).join('\n');
    if (report.isNotEmpty) debugPrint('[purchase] SANITY V2:\n$report');
    return report;
  }

  /// Task 116: старт текущего месячного цикла (мс) — нужен журналу
  /// начислений и санитару.
  Future<int?> billingCycleStartMs() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kBillingCycleStartMs);
  }

  /// Task 116 П.4: перечитать продукты (цены) из магазина.
  /// Вызывается из init и при открытии экрана подписки — цены могли
  /// появиться после активации продуктов в консоли.
  Future<void> refreshProducts() async {
    final ids = <String>{
      fullUnlockId,
      ...tierSubscriptionId.values,
      if (!Platform.isAndroid) ...[
        subDiaryYearId,
        subAssistantYearId,
        subUnlimitedYearId,
      ],
      ...packIds.keys,
      ...packTrIds.keys,
    };
    final response = await _iap.queryProductDetails(ids);
    _products = response.productDetails;
    final missing = response.notFoundIDs;
    if (missing.isNotEmpty) {
      debugPrint('[purchase] не найдены в консоли: $missing');
    }
  }

  Future<bool> buyFullUnlock() async {
    return _buy(fullUnlockId);
  }

  /// Покупка подписки. iOS: год — отдельный продукт. Android: выбирается
  /// базовый план (monthly/yearly) внутри подписки sub_* (task 066).
  /// Task 110: при активной подписке используем plan change
  /// (ChangeSubscriptionParam) — остаток переносится, блокировки «уже
  /// есть» нет.
  Future<bool> buySubscription(SubscriptionTier t,
      {bool yearly = false}) async {
    final subId = tierSubscriptionId[t];
    if (subId == null) return false;

    if (!Platform.isAndroid) {
      final id = yearly ? '${subId}_year' : subId;
      return _buy(id);
    }

    final planId = yearly ? yearlyBasePlanId : monthlyBasePlanId;

    // Task 110: plan change — если есть активная подписка.
    final currentTier = tier.value;
    ChangeSubscriptionParam? changeParam;

    if (currentTier != SubscriptionTier.none) {
      final oldSubId = tierSubscriptionId[currentTier]!;
      final oldPurchase = _findActivePurchase(oldSubId);
      if (oldPurchase != null && oldPurchase is GooglePlayPurchaseDetails) {
        ReplacementMode mode;
        if (currentTier == t) {
          // Тот же тариф, смена периода.
          mode = ReplacementMode.withTimeProration;
        } else {
          // Апгрейд или даунгрейд.
          mode = _tierRank(t) > _tierRank(currentTier)
              ? ReplacementMode.chargeProratedPrice
              : ReplacementMode.withTimeProration;
        }
        changeParam = ChangeSubscriptionParam(
          oldPurchaseDetails: oldPurchase,
          replacementMode: mode,
        );
        debugPrint('[purchase] plan change: $currentTier → $t, mode=$mode');
      }
    }

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
          changeSubscriptionParam: changeParam,
        ),
      );
    }
    debugPrint('[purchase] базовый план $planId не найден в $subId');
    return false;
  }

  /// Task 110: найти активную покупку подписки по productId.
  PurchaseDetails? _findActivePurchase(String productId) {
    // Ищем в _rebuildBuf при restore, иначе — неотложенные покупки.
    // Для plan change нам нужен последний подтверждённый PurchaseDetails.
    // Храним в кэше при _applyPurchase.
    return _activeSubscriptionPurchases[productId];
  }

  /// Task 110: кэш активных покупок подписок для plan change.
  final Map<String, PurchaseDetails> _activeSubscriptionPurchases = {};

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

  /// Task 110: пакет часов расшифровки — тот же consumable-механизм.
  Future<bool> buyPackTr(String packId) => _buy(packId, consumable: true);

  String? priceOf(String productId) => _priceOf(productId);

  String? _priceOf(String productId) {
    for (final p in _products) {
      if (p.id == productId) return p.price;
    }
    return null;
  }

  /// Task 110: префикс для snapshot балансов перед покупкой (возвраты).
  static const _kSnapshotPrefix = 'purchase_snapshot_v1_'; // + productId

  /// Task 110: сохранить snapshot балансов перед покупкой.
  Future<void> _saveSnapshot(String productId) async {
    final p = await SharedPreferences.getInstance();
    final prefix = '$_kSnapshotPrefix$productId';
    final aiPack = await AiHoursService.instance.packMinutesLeft();
    final trPack = await TranscriptionHoursService.instance.packMinutesLeft();
    final trUsed = await TranscriptionHoursService.instance.includedUsedThisMonth();
    await p.setDouble('${prefix}_ai_pack', aiPack);
    await p.setDouble('${prefix}_tr_pack', trPack);
    await p.setDouble('${prefix}_tr_used', trUsed);
    debugPrint('[purchase] snapshot saved for $productId');
  }

  /// Task 110: откатить балансы к snapshot (минус израсходованное после покупки).
  Future<void> _rollbackToSnapshot(String productId) async {
    final p = await SharedPreferences.getInstance();
    final prefix = '$_kSnapshotPrefix$productId';
    final snapAiPack = p.getDouble('${prefix}_ai_pack');
    final snapTrPack = p.getDouble('${prefix}_tr_pack');
    final snapTrUsed = p.getDouble('${prefix}_tr_used');
    if (snapAiPack == null || snapTrPack == null || snapTrUsed == null) return;

    // Текущие значения.
    final curAiPack = await AiHoursService.instance.packMinutesLeft();
    final curTrPack = await TranscriptionHoursService.instance.packMinutesLeft();
    final curTrUsed = await TranscriptionHoursService.instance.includedUsedThisMonth();

    // Откат: snapshot минус то, что потратили ПОСЛЕ покупки.
    // Потраченное = max(0, current - snapshot) для пакетов,
    // для included used — берём snapshot (не откатываем расход).
    final newAiPack = snapAiPack; // пакеты не восстанавливаем — только не перезачисляем
    final newTrPack = snapTrPack;
    final newTrUsed = snapTrUsed;

    await p.setDouble('aihours_pack_minutes_v1', newAiPack);
    await p.setDouble('transcr_pack_minutes_v1', newTrPack);
    await p.setDouble('transcr_included_used_v1', newTrUsed);
    debugPrint('[purchase] rollback to snapshot for $productId: '
        'ai_pack=$newAiPack, tr_pack=$newTrPack, tr_used=$newTrUsed');
  }

  Future<bool> _buy(String productId, {bool consumable = false}) async {
    // Task 110: snapshot перед покупкой для возможного возврата.
    await _saveSnapshot(productId);
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
      if (rebuilt.isEmpty) await p.remove(_kPlayExpiry);
      await p.setInt(_kLastVerifiedMs, DateTime.now().millisecondsSinceEpoch);
      await _applyEffectiveTier();
      debugPrint('[purchase] restore пересобрал набор: $rebuilt, tier=${tier.value}');
    } else {
      final active = p.getStringList(_kActiveSubs) ?? [];
      await _applyEffectiveTier();
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
      await _applyEffectiveTier();
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
          // Task 110: откат к snapshot при ошибке (возможен refund).
          await _rollbackToSnapshot(purchase.productID);
        case PurchaseStatus.canceled:
          lastError.value = 'Покупка отменена.';
          // Task 110: откат к snapshot при отмене.
          await _rollbackToSnapshot(purchase.productID);
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

  /// Task 119: очередь грантов — покупки из стрима/restore могут прийти
  /// пачкой и одновременно пройти «прочитал-нет ключа-начислил» (race),
  /// из-за которого дедуп раньше и пробивался. Гранты сериализуем.
  Future<void> _grantQueue = Future.value();
  Future<T> _serializeGrants<T>(Future<T> Function() fn) {
    final next = _grantQueue.then((_) => fn());
    _grantQueue = next.then((_) {}, onError: (_) {});
    return next;
  }

  /// Task 119: укороченный хэш purchaseToken для ключей дедупа.
  /// Полный токен в prefs не кладём (он же «секрет» сверки).
  static String _shortTok(String t) =>
      t.length > 40 ? t.substring(t.length - 40) : t;

  /// Task 119: кулдаун ИИ-бонуса тарифа (20 дней мес / 320 год).
  Future<bool> _aiBonusCooldownOk(SubscriptionTier t,
      {required bool yearly}) async {
    final p = await SharedPreferences.getInstance();
    final last = p.getInt('$_kAiBonusLastPrefix${t.name}') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final cd = (yearly ? aiBonusCooldownDaysYearly : aiBonusCooldownDays) *
        24 * 60 * 60 * 1000;
    return now - last >= cd;
  }

  Future<void> _markAiBonusGranted(SubscriptionTier t) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('$_kAiBonusLastPrefix${t.name}',
        DateTime.now().millisecondsSinceEpoch);
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
      // Task 087: сохраняем реальный purchaseToken для сверки.
      await _recordRealToken(purchase);
      await _applyPack(purchase);
      return;
    }
    if (packTrIds.containsKey(productId)) {
      // Task 110: пакет часов расшифровки — тот же механизм идемпотентности.
      await _recordRealToken(purchase);
      await _applyPackTr(purchase);
      return;
    }
    final t = _tierOfProduct(productId);
    if (t != SubscriptionTier.none) {
      // Task 087: сохраняем реальный purchaseToken для сверки.
      await _recordRealToken(purchase);

      // Task 116 П.3/П.8: Play возвращает покупку ОТМЕНЁННОЙ подписки
      // ещё на grace-участке, и restorePurchases может отдать её повторно
      // после истечения периода. Если expiryTimeMillis уже в прошлом —
      // подписка не действует: снимаем тариф, НЕ начисляем бонусы и НЕ
      // кладём в rebuild-буфер. Пакеты (бессрочные) не трогаем.
      if (await _isSubscriptionExpired(purchase)) {
        await _deactivateExpiredSubscription(productId);
        return;
      }

      // 20.10: бонусные ИИ-часы тарифа (Дневник 10 / Ассистент 20 / Безлимит 40).
      // Раньше были только текстом в карточке — покупатель не получал ничего.
      final pref = await SharedPreferences.getInstance();
      // Task 119 (БЛОКЕР, возврат «2210 ч»): дедуп грантов по purchaseToken.
      // orderId на Android плагин часто не отдаёт (purchaseID=null), а
      // transactionDate меняется у КАЖДОГО авто-продления — дедуп по ним
      // пробивался, и тестовая подписка (продление каждые 5 мин) накидала
      // 24 ч × 8 и 10 ИИ-ч × 5 за 40 минут. serverVerificationData
      // (purchaseToken) при авто-продлении СТАБИЛЕН — ключ по нему.
      // Часы и ИИ-бонус разведены: часы грантим по токену (покупка после
      // отмены = новый токен = честные +24 ч), бонус — по кулдауну 20 дней
      // на тир (схема «купил-отменил-купил» не фармит ИИ-часы). Пакеты
      // (разовые) без кулдауна — это товар.
      final rawTok = purchase.verificationData.serverVerificationData.trim();
      final yearly = productId.endsWith('_year');
      if (rawTok.isEmpty) {
        // fail-closed: лучше недоначислить, чем размножить. Токен Play
        // отдаёт всегда; пусто — аномалия доставки, грант пропускаем.
        lastSanitizeReport += '; refusal:$productId:no-token@${DateTime.now().millisecondsSinceEpoch}';
        debugPrint('[purchase] нет purchaseToken — грант $productId '
            'пропущен (fail-closed)');
      } else {
        final tokKey = 'tok:${_shortTok(rawTok)}';
        await _serializeGrants(() async {
          // Список перечитываем внутри очереди — за время ожидания другой
          // грант мог уже записать свой ключ (race fix).
          final applied =
              (pref.getStringList(_kSubBonusApplied) ?? []).toSet();
          if (applied.contains(tokKey)) {
            debugPrint('[purchase] грант $productId по токену уже применён'
                ' (авто-продление/redelivery) — skip');
            return;
          }
          // Включённые часы расшифровки — по токену покупки.
          await ensureBillingCycle();
          await TranscriptionHoursService.instance.addIncludedHours(
              includedTranscriptionHours[t]?.toDouble() ?? 0);
          // ИИ-бонус — по кулдауну тарифа, отмена подписки его НЕ сбрасывает.
          if (await _aiBonusCooldownOk(t, yearly: yearly)) {
            final bonus = includedHours[t] ?? 0;
            if (bonus > 0) {
              await AiHoursService.instance.addMonthlyBonus(bonus.toDouble());
              debugPrint('[purchase] бонус ИИ-часов +$bonus за $t');
            }
            await _markAiBonusGranted(t);
          } else {
            debugPrint('[purchase] ИИ-бонус $t в кулдауне — пропуск');
          }
          applied.add(tokKey);
          await pref.setStringList(_kSubBonusApplied, applied.toList());
        });
      }

      if (_rebuild) {
        // Идёт пересборка — копим подтверждённые подписки до финализации.
        _rebuildBuf.add(productId);
        return;
      }
      final p = pref;
      final set = (p.getStringList(_kActiveSubs) ?? []).toSet()..add(productId);
      await p.setStringList(_kActiveSubs, set.toList());
      // Fix 19.10: Play отдаёт expiryTimeMillis только внутри originalJson
      // (у PurchaseWrapper нет отдельного поля). Парсим JSON покупки.
      try {
        final raw = purchase is GooglePlayPurchaseDetails
            ? purchase.billingClientPurchase.originalJson
            : null;
        if (raw != null && raw.isNotEmpty) {
          final j = jsonDecode(raw) as Map<String, dynamic>;
          final exp = int.tryParse('${j['expiryTimeMillis'] ?? ''}');
          if (exp != null && exp > 0) {
            await p.setInt(_kPlayExpiry, exp);
            debugPrint('[purchase] expiry сохранён: '
                '${DateTime.fromMillisecondsSinceEpoch(exp)}');
          }
        }
      } catch (e) {
        debugPrint('[purchase] expiry parse: $e');
      }
      await _applyEffectiveTier();
      return;
    }
    debugPrint('[purchase] неизвестный продукт $productId — приём отключён');
  }

  /// Task 116 П.3/П.8: true — у подписки expiryTimeMillis в прошлом
  /// (отменена/истекла/отозвана в Play). Тестовая подписка продлевается
  /// каждые ~5 мин; после отмены expiry сжимается до минут и быстро
  /// оказывается в прошлом. Нет данных (iOS/пустой originalJson) —
  /// не решаем, считаем живой (решит restore/серверная сверка).
  Future<bool> _isSubscriptionExpired(PurchaseDetails purchase) async {
    try {
      final raw = purchase is GooglePlayPurchaseDetails
          ? purchase.billingClientPurchase.originalJson
          : null;
      if (raw == null || raw.isEmpty) return false;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final exp = int.tryParse('${j['expiryTimeMillis'] ?? ''}');
      if (exp == null || exp <= 0) return false;
      return exp < DateTime.now().millisecondsSinceEpoch;
    } catch (_) {
      return false;
    }
  }

  /// Task 116 П.3/П.8: снять истёкшую подписку — убрать из активного
  /// набора и из rebuild-буфера restore. Эффективный тариф пересчитается;
  /// остаток включённых часов НЕ продлевается, купленные пакеты целы.
  /// Task 116 (Б, Славан 23.10): при отмене/истечении/возврате подписки —
  /// немедленный возврат в бесплатный тариф: включённые часы расшифровки
  /// сгорают (борьба со схемой «купил → отменил → вернул деньги → пользуюсь»).
  /// Купленные за деньги пакеты остаются. ИИ-бонус месяца сгорает сам:
  /// база = тариф = none → включённая часть = 0.
  Future<void> _hardResetToFree() async {
    try {
      await TranscriptionHoursService.instance.resetToFree();
    } catch (e) {
      debugPrint('[purchase] resetToFree: $e');
    }
  }

  Future<void> _deactivateExpiredSubscription(String productId) async {
    final p = await SharedPreferences.getInstance();
    final set = (p.getStringList(_kActiveSubs) ?? []).toSet()
      ..remove(productId);
    await p.setStringList(_kActiveSubs, set.toList());
    // Не попасть в пересобранный restore-набор.
    _rebuildBuf.remove(productId);
    // Просроченный expiry Play не кэшируем — срок доступа кончился.
    final exp = p.getInt(_kPlayExpiry);
    if (exp != null && exp < DateTime.now().millisecondsSinceEpoch) {
      await p.remove(_kPlayExpiry);
    }
    await _applyEffectiveTier();
    await _hardResetToFree();
    debugPrint('[purchase] подписка $productId истекла — тариф снят, часы сброшены (Б)');
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

  /// Task 110: зачислить пакет часов расшифровки ровно один раз на один платёж.
  /// Та же дедупликация по токену, что и в _applyPack.
  Future<void> _applyPackTr(PurchaseDetails purchase) async {
    final productId = purchase.productID;
    final token = purchase.purchaseID ??
        '${purchase.productID}:${purchase.transactionDate}';
    final p = await SharedPreferences.getInstance();
    final applied = (p.getStringList(_kAppliedPacks) ?? []).toSet();
    if (applied.contains(token)) {
      debugPrint('[purchase] пакет расшифровки $productId уже зачислен ($token) — skip');
      return;
    }
    await TranscriptionHoursService.instance.addPackHours(packTrIds[productId]!);
    applied.add(token);
    await p.setStringList(_kAppliedPacks, applied.toList());
    debugPrint('[purchase] пакет расшифровки $productId зачислен: '
        '+${packTrIds[productId]} ч (токен $token)');
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

  /// Task 087: сохранить реальный purchaseToken (Play) для серверной сверки.
  /// Токен не логируем.
  /// Task 110: для подписок также кэшируем PurchaseDetails для plan change.
  Future<void> _recordRealToken(PurchaseDetails purchase) async {
    try {
      final token = purchase.verificationData.serverVerificationData;
      if (token.isEmpty) return;
      await BillingVerifyService.instance
          .recordPurchaseToken(purchase.productID, token);
      // Task 110: если это подписка — кэшируем для plan change.
      final t = _tierOfProduct(purchase.productID);
      if (t != SubscriptionTier.none) {
        _activeSubscriptionPurchases[purchase.productID] = purchase;
      }
    } catch (_) {}
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
  /// Task 087: переименовано и сделано публичным для BillingVerifyService.
  Future<void> deactivateTierForVerify(SubscriptionTier t) async {
    final subId = tierSubscriptionId[t];
    if (subId == null) return;
    final p = await SharedPreferences.getInstance();
    final set = (p.getStringList(_kActiveSubs) ?? []).toSet()..remove(subId);
    await p.setStringList(_kActiveSubs, set.toList());
    await _applyEffectiveTier();
    // Task 116 (Б): возврат средств/отзыв — тот же жёсткий сброс часов.
    await _hardResetToFree();
  }

  /// Task 096: текущий срок действия кода (null — нет кода или бессрочно).
  Future<DateTime?> codeExpiryDate() async {
    final p = await SharedPreferences.getInstance();
    final expMs = p.getInt(_kCodeExpiry);
    if (expMs != null) return DateTime.fromMillisecondsSinceEpoch(expMs);
    // Task 110 fix: если кода нет — дата окончания активной Play-подписки.
    final playMs = p.getInt(_kPlayExpiry);
    if (playMs != null && playMs > DateTime.now().millisecondsSinceEpoch) {
      return DateTime.fromMillisecondsSinceEpoch(playMs);
    }
    return null;
  }

  /// Task 089/114: выдать тариф из кода активации. ЕДИНАЯ точка установки
  /// tier+expiry+бонусных ИИ-часов из кода (см. шапку файла, task 114).
  ///
  /// Накопление срока: новый срок = max(текущий конец доступа, сейчас)
  /// + период кода. Тот же тариф (месяц+месяц) и другой тариф (остаток
  /// не теряется) дают одну формулу. Период берём из typeKey (30/365 дней);
  /// [payloadExpiresAt] больше не используется как абсолютная дата доступа.
  ///
  /// Бонусные ИИ-часы тарифа (Дневник 10 / Ассистент 20 / Безлимит 40)
  /// начисляются один раз на каждый активированный код (дедуп по
  /// 'code:<rawCode>' в _kSubBonusApplied).
  Future<void> activateCode({
    required SubscriptionTier codeTier,
    required String typeKey,
    required String rawCode,
    DateTime? payloadExpiresAt,
  }) async {
    final p = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final isYearly = typeKey.endsWith('_YEAR');

    final currentEnd = await codeExpiryDate();
    final newExpiry = computeCodeExpiry(
      now: now,
      currentEnd: currentEnd,
      yearly: isYearly,
    );

    // Сохраняем выданный кодом тариф (если сильнее уже сохранённого) —
    // эффективный тариф всё равно пересчитает max с Play-подписками.
    final storedName = p.getString(_kCodeTier);
    final storedTier = SubscriptionTier.values.firstWhere(
      (e) => e.name == storedName,
      orElse: () => SubscriptionTier.none,
    );
    final tierToStore = _tierRank(codeTier) >= _tierRank(storedTier)
        ? codeTier
        : storedTier;

    await p.setString(_kCodeTier, tierToStore.name);
    await p.setInt(_kCodeExpiry, newExpiry.millisecondsSinceEpoch);
    await p.setString(
        _kCodePeriod, isYearly ? yearlyBasePlanId : monthlyBasePlanId);

    // Бонусные ИИ-часы тарифа — один раз на код + кулдаун тира (task 119):
    // схема «активировал-дал сгореть-активировал» не фармит бонус.
    final bonus = includedHours[codeTier] ?? 0;
    if (bonus > 0 && rawCode.isNotEmpty) {
      final applied = (p.getStringList(_kSubBonusApplied) ?? []).toSet();
      final key = 'code:$rawCode';
      if (!applied.contains(key) &&
          await _aiBonusCooldownOk(codeTier, yearly: isYearly)) {
        // 22.10 (Славан): бонус тарифа СГОРАЕТ в конце месяца — месячная корзина.
        await AiHoursService.instance.addMonthlyBonus(bonus);
        applied.add(key);
        await p.setStringList(_kSubBonusApplied, applied.toList());
        await _markAiBonusGranted(codeTier);
        debugPrint('[purchase] код $typeKey: бонус ИИ-часов +$bonus');
      } else if (!applied.contains(key)) {
        debugPrint('[purchase] код $typeKey: ИИ-бонус $codeTier в кулдауне — пропуск');
      }
    }

    // Task 115: якорь месячного цикла (первый тариф) + накопление
    // включённых часов расшифровки (24 + 120 = 144 при апгрейде).
    await ensureBillingCycle();
    await TranscriptionHoursService.instance
        .addIncludedHours(includedTranscriptionHours[codeTier]?.toDouble() ?? 0);

    await _applyEffectiveTier();
  }

  /// Task 114: чистая формула накопления срока кода.
  /// base = max(currentEnd, now); срок = base + период.
  /// Покрыто юнит-тестом (test/code_expiry_test.dart).
  static DateTime computeCodeExpiry({
    required DateTime now,
    required DateTime? currentEnd,
    required bool yearly,
  }) {
    final base = (currentEnd != null && currentEnd.isAfter(now))
        ? currentEnd
        : now;
    return base.add(Duration(days: yearly ? 365 : 30));
  }

  /// Task 114: период последнего активированного кода ('monthly'/'yearly').
  /// null — кода не было. Для честного отображения периода на экране подписки.
  Future<String?> codePeriod() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kCodePeriod);
  }

  /// Task 115: первый тариф (код/покупка) ставит якорь месячного цикла.
  /// Апгрейды в середине цикла якорь НЕ двигают.
  Future<void> ensureBillingCycle() async {
    final p = await SharedPreferences.getInstance();
    if (p.getInt(_kBillingCycleStartMs) == null) {
      await p.setInt(
          _kBillingCycleStartMs, DateTime.now().millisecondsSinceEpoch);
    }
  }

  /// +1 месяц с клампом дня (31.01 → 28/29.02). Покрыто юнит-тестом.
  static DateTime addMonthsClamped(DateTime d, int months) {
    final total = d.month - 1 + months;
    final y = d.year + total ~/ 12;
    final m = total % 12 + 1;
    const daysIn = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    var maxDay = daysIn[m - 1];
    if (m == 2 && (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0))) {
      maxDay = 29;
    }
    final day = d.day <= maxDay ? d.day : maxDay;
    return DateTime(y, m, day, d.hour, d.minute, d.second);
  }

  /// Task 115: если наступил следующий месяц цикла — сдвигаем cycleStart
  /// (на случай пропуска нескольких месяцев — while). true — цикл обновлён;
  /// кошельки (TranscriptionHoursService/AiHoursService) при true сбрасывают
  /// used и выдают свежий пакет текущего тарифа (остаток сгорает).
  Future<bool> rolloverBillingCycleIfNeeded() async {
    final p = await SharedPreferences.getInstance();
    final startMs = p.getInt(_kBillingCycleStartMs);
    if (startMs == null) return false;
    var start = DateTime.fromMillisecondsSinceEpoch(startMs);
    final now = DateTime.now();
    var changed = false;
    while (!now.isBefore(addMonthsClamped(start, 1))) {
      start = addMonthsClamped(start, 1);
      changed = true;
    }
    if (changed) {
      await p.setInt(_kBillingCycleStartMs, start.millisecondsSinceEpoch);
    }
    return changed;
  }

  /// Эффективный тариф: максимум из Play-подписок и активного кода (089).
  /// Код хранится в code_activated_*; пустой срок = бессрочно.
  Future<void> _applyEffectiveTier() async {
    final p = await SharedPreferences.getInstance();
    final playTier = _tierFromProducts(p.getStringList(_kActiveSubs) ?? []);
    var codeTier = SubscriptionTier.none;
    final codeName = p.getString(_kCodeTier);
    if (codeName != null) {
      final ct = SubscriptionTier.values.firstWhere(
          (e) => e.name == codeName,
          orElse: () => SubscriptionTier.none);
      final expMs = p.getInt(_kCodeExpiry);
      final valid =
          expMs == null || DateTime.now().millisecondsSinceEpoch < expMs;
      if (valid) codeTier = ct;
    }
    tier.value =
        _tierRank(playTier) >= _tierRank(codeTier) ? playTier : codeTier;
    // Task 114: оповещаем UI (шапка подписки/главной) — тариф или срок
    // могли измениться. Слушатели перечитывают балансы без пересоздания.
    planRevision.value++;
  }

  static int _tierRank(SubscriptionTier t) => switch (t) {
        SubscriptionTier.none => 0,
        SubscriptionTier.diary => 1,
        SubscriptionTier.assistant => 2,
        SubscriptionTier.unlimited => 3,
      };

  Future<void> dispose() async {
    await _sub?.cancel();
  }
}
