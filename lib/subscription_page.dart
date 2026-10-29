// Task 065/066/068: экран «Подписка» — 3 тарифа (Месяц/Год) + пакеты ИИ-часов.
// Логика покупок из PurchaseService (066), оформление — дизайн V3 (068).
import 'package:activation_codes/activation_codes.dart' as ac;
import 'package:flutter/material.dart';

import 'app_strings.dart';
import 'services/ai_hours_service.dart';
import 'services/code_activation_service.dart';
import 'services/purchase_service.dart';
import 'services/transcription_hours_service.dart';
import 'theme/app_theme.dart';
import 'widgets/dicta_ui.dart';
import 'main_shell.dart';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  final _purchases = PurchaseService.instance;

  bool _yearly = false;
  bool _busy = false;
  double _balanceHours = 0;
  double _transcrBalance = 0;
  bool _transcrUnlimited = false;
  DateTime? _expiryDate;

  @override
  void initState() {
    super.initState();
    // Task 116 П.4: перечитать цены (продукты могли активироваться недавно).
    PurchaseService.instance.refreshProducts().then((_) {
      if (mounted) setState(() {});
    });
    _refreshBalance();
    _initPeriodFromPlan();
    // Task 114: шапка обновляется СРАЗУ после активации кода/покупки —
    // без входа-выхода со страницы (planRevision в PurchaseService).
    _purchases.planRevision.addListener(_onPlanChanged);
    // Task 116 П.4: переопрос цен при открытии — продукты, добавленные
    // в консоль после установки приложения, подхватываются без рестарта.
    // planRevision перечитает шапку/карточки, когда цены придут.
    _purchases.refreshProducts();
  }

  @override
  void dispose() {
    _purchases.planRevision.removeListener(_onPlanChanged);
    super.dispose();
  }

  void _onPlanChanged() {
    if (mounted) _refreshBalance();
  }

  /// Task 114 п.5: переключатель месяц/год изначально показывает ПЕРИОД,
  /// который реально активен по коду (честные карточки, не «всегда месяц»).
  Future<void> _initPeriodFromPlan() async {
    final period = await _purchases.codePeriod();
    if (!mounted) return;
    if (period == PurchaseService.yearlyBasePlanId && !_yearly) {
      setState(() => _yearly = true);
    }
  }

  Future<void> _refreshBalance() async {
    final b = await AiHoursService.instance.balanceHours();
    final tb = await TranscriptionHoursService.instance.balanceHours();
    final exp = await PurchaseService.instance.codeExpiryDate();
    if (mounted) {
      setState(() {
        _balanceHours = b;
        _transcrBalance = tb;
        _transcrUnlimited = TranscriptionHoursService.instance.isUnlimited;
        _expiryDate = exp;
      });
    }
  }

  String _tierName(BuildContext context, SubscriptionTier t) => switch (t) {
        SubscriptionTier.diary => AppStrings.t('sub_tier_diary', context),
        SubscriptionTier.assistant => AppStrings.t('sub_tier_assistant', context),
        SubscriptionTier.unlimited => AppStrings.t('sub_tier_unlimited', context),
        SubscriptionTier.none => '',
      };

  String _tierDesc(BuildContext context, SubscriptionTier t) => switch (t) {
        SubscriptionTier.diary => AppStrings.t('sub_tier_diary_desc', context),
        SubscriptionTier.assistant =>
          AppStrings.t('sub_tier_assistant_desc', context),
        SubscriptionTier.unlimited =>
          AppStrings.t('sub_tier_unlimited_desc', context),
        SubscriptionTier.none => '',
      };

  Future<void> _buyTier(SubscriptionTier t, {bool? yearly}) async {
    if (_busy) return;
    setState(() => _busy = true);
    // Fix 19.10: кнопка «Подписаться на год» передаёт целевой период явно,
    // иначе уходит текущий переключатель (месяц) и Play отвечает developerError.
    final ok = await _purchases.buySubscription(t, yearly: yearly ?? _yearly);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.t('sub_purchased', context))),
      );
      await _refreshBalance();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.t('store_unavailable', context))),
      );
    }
  }

  Future<void> _buyPack(String packId) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await _purchases.buyPack(packId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.t('sub_purchased', context))),
      );
      await _refreshBalance();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.t('store_unavailable', context))),
      );
    }
  }

  // Task 083: restore с индикатором и результатом — не заглушка.
  Future<void> _restore() async {
    setState(() => _busy = true);
    await _purchases.restore();
    await _refreshBalance();
    if (!mounted) return;
    setState(() => _busy = false);

    final tier = _purchases.tier.value;
    final unlocked = _purchases.unlocked.value;
    final hasPacks = _balanceHours > 0;

    String message;
    if (tier != SubscriptionTier.none || unlocked || hasPacks) {
      final parts = <String>[];
      if (tier != SubscriptionTier.none) {
        parts.add(AppStrings.tf('sub_status_tier', context, {
          't': _tierName(context, tier),
        }));
      }
      if (unlocked) parts.add(AppStrings.t('sub_full_unlock_status', context));
      if (hasPacks) parts.add(AppStrings.t('sub_restore_found_packs', context));
      message = parts.join('\n');
    } else {
      message = AppStrings.t('sub_restore_not_found', context);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  // Task 089: активация кодов через единый модуль activation_codes.
  Future<void> _promo() async {
    if (!CodeActivationService.instance.isReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Активация кодов недоступна — нет ключа')),
      );
      return;
    }

    final result = await showDialog<ac.CodeResult>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.t('sub_promo_title', context)),
        content: SizedBox(
          width: double.maxFinite,
          child: ac.ActivationCodeField(
            onRedeem: (code) async {
              var r = await CodeActivationService.instance.redeem(code);
              // Task 104: v1-код без HMAC-ключа → needsOnline.
              // Направляем на сервер через /session.
              if (!r.ok && r.error == ac.CodeError.needsOnline) {
                r = await CodeActivationService.instance.redeemOnline(code);
              }
              if (r.ok) {
                await CodeActivationService.instance.applyCodeResult(r, rawCode: code);
              }
              return r;
            },
            accentColor: DictaTokens.of(context).mint,
            hintText: 'DICTA-...',
            messages: {
              ac.CodeError.needsOnline: 'Требуется интернет для проверки кода',
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppStrings.t('long_transcribe_cancel', context)),
          ),
        ],
      ),
    );

    if (result != null && result.ok && mounted) {
      await _refreshBalance();
      final typeKey = result.typeKey ?? '';
      final tier = CodeActivationService.instance.tierOfTypeKey(typeKey);
      final pack = CodeActivationService.instance.packOfTypeKey(typeKey);
      String msg;
      if (tier != SubscriptionTier.none) {
        msg = 'Код активирован: тариф ${_tierName(context, tier)}'
            '${result.expiresAt != null ? ' до ${_fmtDate(result.expiresAt!)}' : ''}';
      } else if (pack != null) {
        msg = 'Код активирован: +${pack.toStringAsFixed(0)} ч ИИ';
      } else {
        msg = 'Код активирован!';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
      );
    }
  }

  String _fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      bottomNavigationBar: DictaBottomNav(
        index: 3,
        onTap: (i) {
          Navigator.of(context).popUntil((r) => r.isFirst);
          MainShell.requestedTab.value = i;
        },
      ),
      body: DictaBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(AppStrings.t('sub_title', context)),
        ),
        body: ValueListenableBuilder<SubscriptionTier>(
          valueListenable: _purchases.tier,
          builder: (context, tier, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: _purchases.unlocked,
              builder: (context, unlocked, _) {
                final productsLoaded = _purchases.products.isNotEmpty;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                  children: [
                    _statusCard(context, tier, unlocked),
                    if (!productsLoaded) ...[
                      const SizedBox(height: 12),
                      _storeBanner(context),
                    ],
                    const SizedBox(height: 16),
                    _periodToggle(context),
                    const SizedBox(height: 12),
                    for (final t in const [
                      SubscriptionTier.diary,
                      SubscriptionTier.assistant,
                      SubscriptionTier.unlimited,
                    ]) ...[
                      _tierCard(context, t, current: t == tier),
                    ],
                    const SizedBox(height: 10),
                    _packsTrSection(context),
                    const SizedBox(height: 14),
                    _packsSection(context),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Task 083: restore с индикатором.
                        ValueListenableBuilder<bool>(
                          valueListenable: _purchases.restoring,
                          builder: (context, restoring, _) {
                            if (restoring) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(
                                      width: 14, height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      AppStrings.t('sub_restore_checking', context),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: DictaTokens.of(context).ink3,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return TextButton(
                              onPressed: _busy ? null : _restore,
                              child: Text(AppStrings.t('sub_restore', context),
                                  style: TextStyle(color: DictaTokens.of(context).mint)),
                            );
                          },
                        ),
                        Text('·', style: TextStyle(color: DictaTokens.of(context).ink3)),
                        TextButton(
                          onPressed: _busy ? null : _promo,
                          child: Text(AppStrings.t('sub_promo', context),
                              style: TextStyle(color: DictaTokens.of(context).mint)),
                        ),
                      ],
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    ),
    );
  }

  Widget _statusCard(BuildContext context, SubscriptionTier tier, bool unlocked) {
    final tk = DictaTokens.of(context);
    final rows = <Widget>[];
    if (tier == SubscriptionTier.none) {
      rows.add(Text(AppStrings.t('sub_status_none', context),
          style: TextStyle(fontSize: 12.5, color: tk.ink2, height: 1.5)));
      // Славан 28.10: остатки пакетов видны и без тарифа — как при тарифе.
      rows.add(const SizedBox(height: 6));
      rows.add(FutureBuilder<String>(
        future: TranscriptionHoursService.instance.balanceLabel(),
        builder: (context, snap) {
          final label = snap.data ?? '';
          if (label.isEmpty) return const SizedBox.shrink();
          return Text(label,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: tk.ink));
        },
      ));
      rows.add(const SizedBox(height: 4));
      rows.add(FutureBuilder<String>(
        future: AiHoursService.instance.balanceLabel(),
        builder: (context, snap) {
          final label = snap.data ?? '';
          if (label.isEmpty) return const SizedBox.shrink();
          return Text(label,
              style: TextStyle(fontSize: 11.5, color: tk.ink3));
        },
      ));
    } else {
      // Task 110: шапка — тариф · дата окончания · часы расшифровки.
      final tierName = _tierName(context, tier);
      String header = tierName;
      if (_expiryDate != null) {
        header += ' · ${AppStrings.tf('sub_expiry_label', context, {
          'd': _fmtDate(_expiryDate!),
        })}';
      }
      rows.add(Text(header,
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: tk.mint)));
      rows.add(const SizedBox(height: 6));
      // Часы расшифровки — основная строка.
      rows.add(FutureBuilder<String>(
        future: TranscriptionHoursService.instance.balanceLabel(),
        builder: (context, snap) {
          final label = snap.data ?? '';
          return Text(label,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: tk.ink));
        },
      ));
      rows.add(const SizedBox(height: 4));
      // ИИ-часы — вторичная строка.
      rows.add(Text(
          AppStrings.tf('sub_status_balance', context,
              {'h': _balanceHours.toStringAsFixed(1)}),
          style: TextStyle(fontSize: 11.5, color: tk.ink3)));
    }
    if (unlocked) {
      rows.add(const SizedBox(height: 6));
      rows.add(Text(AppStrings.t('sub_full_unlock_status', context),
          style: TextStyle(fontSize: 12, color: tk.mint)));
    }
    return DictaCard(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows));
  }

  Widget _storeBanner(BuildContext context) {
    final tk = DictaTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tk.gold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tk.gold.withValues(alpha: 0.30)),
      ),
      child: Text(AppStrings.t('sub_store_banner', context),
          style: TextStyle(fontSize: 12.5, color: tk.gold, height: 1.5)),
    );
  }

  Widget _periodToggle(BuildContext context) {
    final tk = DictaTokens.of(context);
    Widget seg(bool yearly, String label, String? sub) {
      final on = _yearly == yearly;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: _busy ? null : () => setState(() => _yearly = yearly),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: on ? tk.mint : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: on ? AppColors.mintInk : tk.ink3)),
              if (sub != null && on)
                Text(sub,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.mintInk.withValues(alpha: 0.85))),
            ]),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tk.line),
      ),
      child: Row(children: [
        seg(false, AppStrings.t('sub_period_month', context), null),
        seg(true, AppStrings.t('sub_period_year', context), AppStrings.t('sub_year_badge', context)),
      ]),
    );
  }

  Widget _tierCard(BuildContext context, SubscriptionTier t,
      {required bool current}) {
    final tk = DictaTokens.of(context);
    final price = _purchases.priceOfSubscription(t, yearly: _yearly);
    final periodHint = _yearly
        ? AppStrings.t('sub_year_hint', context)
        : AppStrings.t('sub_month_hint', context);
    final best = _yearly && t == SubscriptionTier.unlimited;
    final hours = PurchaseService.includedHours[t] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: tk.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: best
              ? tk.gold
              : (current ? tk.mint.withValues(alpha: 0.9) : tk.line),
        ),
        gradient: best
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  tk.gold.withValues(alpha: 0.13),
                  tk.gold.withValues(alpha: 0.03),
                ])
            : null,
      ),
      child: Stack(clipBehavior: Clip.none, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_tierName(context, t),
                      style: const TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(_tierDesc(context, t),
                      style: TextStyle(fontSize: 10.5, color: tk.ink3)),
                ],
              ),
            ),
            if (price != null)
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(price, style: tk.mono(19, FontWeight.w700, tk.ink)),
                Text('/ $periodHint',
                    style: TextStyle(fontSize: 10.5, color: tk.ink3)),
              ])
            else
              SizedBox(
                width: 120,
                child: Text(AppStrings.t('sub_price_pending', context),
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11, color: tk.ink3)),
              ),
          ]),
          const SizedBox(height: 9),
          // Главное — включённые часы расшифровки (Дневник 24 ч · Ассистент 120 ч · Безлимит ∞)
          Text(
              t == SubscriptionTier.unlimited
                  ? AppStrings.t('sub_transcr_unlimited', context)
                  : AppStrings.tf('sub_transcr_included', context,
                      {'h': '${PurchaseService.includedTranscriptionHours[t]}'}),
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: tk.ink)),
          const SizedBox(height: 3),
          // Бонус — ИИ-часы для онлайн-итогов (одной строкой, без дубля)
          Text(AppStrings.tf('sub_ai_bonus', context, {'h': '$hours'}),
              style: TextStyle(fontSize: 11, color: tk.ink3)),
          const SizedBox(height: 10),
          // Task 110: кнопка смены тарифа/периода.
          // Если это текущий тариф — показываем кнопку смены периода.
          // Если другой тариф — кнопку «Перейти» с пояснением.
          SizedBox(
            width: double.infinity,
            child: current
                ? (() {
                    // Task 110 fix (приёмка 22:54): «Текущий тариф» как статус;
                    // покупка другого периода — явная кнопка «Подписаться на …».
                    final otherYearly = !_yearly;
                    final switchLabel = otherYearly
                        ? AppStrings.t('sub_buy_year', context)
                        : AppStrings.t('sub_buy_month', context);
                    return Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: tk.mint.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(AppStrings.t('sub_current_plan', context),
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: tk.mint)),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed:
                              _busy ? null : () => _buyTier(t, yearly: otherYearly),
                          child: Text(switchLabel),
                        ),
                        const SizedBox(height: 4),
                        Text(AppStrings.t('sub_switch_hint', context),
                            style: TextStyle(fontSize: 10.5, color: tk.ink3)),
                      ],
                    );
                  })()
                : (best
                    ? ElevatedButton(
                        onPressed: _busy ? null : () => _buyTier(t),
                        child: Text(
                            '${AppStrings.t('sub_buy', context)} · ${price ?? ''}'),
                      )
                    : OutlinedButton(
                        onPressed: _busy ? null : () => _buyTier(t),
                        child: Text(AppStrings.t('sub_buy', context)),
                      )),
          ),
        ]),
        if (best)
          Positioned(
            top: -20,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: tk.gold, borderRadius: BorderRadius.circular(999)),
              child: Text(AppStrings.t('sub_best_price_year', context),
                  style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF3A2C00))),
            ),
          ),
      ]),
    );
  }

  Widget _packsSection(BuildContext context) {
    final tk = DictaTokens.of(context);
    final entries = PurchaseService.packIds.entries.toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DictaSectionTitle(AppStrings.t('sub_packs_title', context)),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.4,
        children: [
          for (final e in entries)
            // Task 116 П.4: без заглушек «цена появится после запуска» —
            // карточка пакета показывается только когда цена реально
            // пришла из магазина.
            if (_purchases.priceOf(e.key) != null)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _busy ? null : () => _buyPack(e.key),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: tk.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: tk.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(AppStrings.tf('sub_hours_short', context, {'n': e.value.toStringAsFixed(0)}),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(
                          _purchases.priceOf(e.key)!,
                          style: tk.mono(12.5, FontWeight.w600, tk.mint)),
                    ],
                  ),
                ),
              ),
        ],
      ),
      const SizedBox(height: 6),
      Text(AppStrings.t('sub_packs_note', context),
          style: TextStyle(fontSize: 11, color: tk.ink3, height: 1.5)),
    ]);
  }

  /// Task 110: пакеты часов расшифровки — та же сетка 2×2.
  Widget _packsTrSection(BuildContext context) {
    final tk = DictaTokens.of(context);
    final entries = PurchaseService.packTrIds.entries.toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DictaSectionTitle(AppStrings.t('sub_packs_tr_title', context)),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.4,
        children: [
          for (final e in entries)
            // Task 116 П.4: карточка только с реальной ценой из магазина.
            if (_purchases.priceOf(e.key) != null)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _busy ? null : () => _buyPackTr(e.key),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: tk.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: tk.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(AppStrings.tf('sub_hours_short', context, {'n': e.value.toStringAsFixed(0)}),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(
                          _purchases.priceOf(e.key)!,
                          style: tk.mono(12.5, FontWeight.w600, tk.mint)),
                    ],
                  ),
                ),
              ),
        ],
      ),
      const SizedBox(height: 6),
      Text(AppStrings.t('sub_packs_tr_note', context),
          style: TextStyle(fontSize: 11, color: tk.ink3, height: 1.5)),
    ]);
  }

  /// Task 110: покупка пакета часов расшифровки.
  Future<void> _buyPackTr(String packId) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await _purchases.buyPackTr(packId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.t('sub_purchased', context))),
      );
      await _refreshBalance();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.t('store_unavailable', context))),
      );
    }
  }
}
