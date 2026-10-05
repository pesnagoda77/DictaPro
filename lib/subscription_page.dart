// Task 065/066/068: экран «Подписка» — 3 тарифа (Месяц/Год) + пакеты ИИ-часов.
// Логика покупок из PurchaseService (066), оформление — дизайн V3 (068).
import 'package:flutter/material.dart';

import 'app_strings.dart';
import 'services/ai_hours_service.dart';
import 'services/purchase_service.dart';
import 'theme/app_theme.dart';
import 'widgets/dicta_ui.dart';

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

  @override
  void initState() {
    super.initState();
    _refreshBalance();
  }

  Future<void> _refreshBalance() async {
    final b = await AiHoursService.instance.balanceHours();
    if (mounted) setState(() => _balanceHours = b);
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

  Future<void> _buyTier(SubscriptionTier t) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await _purchases.buySubscription(t, yearly: _yearly);
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

  Future<void> _promo() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.t('sub_promo_title', context)),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            labelText: AppStrings.t('sub_promo_hint', context),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppStrings.t('long_transcribe_cancel', context)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(AppStrings.t('save', context)),
          ),
        ],
      ),
    );
    if (code != null && code.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.t('sub_promo_pending', context))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DictaBackground(
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
    );
  }

  Widget _statusCard(BuildContext context, SubscriptionTier tier, bool unlocked) {
    final tk = DictaTokens.of(context);
    final rows = <Widget>[];
    if (tier == SubscriptionTier.none) {
      rows.add(Text(AppStrings.t('sub_status_none', context),
          style: TextStyle(fontSize: 12.5, color: tk.ink2, height: 1.5)));
    } else {
      rows.add(Text(
        AppStrings.tf('sub_status_tier', context, {'t': _tierName(context, tier)}),
        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: tk.mint),
      ));
    }
    rows.add(const SizedBox(height: 6));
    rows.add(Text(
        AppStrings.tf('sub_status_balance', context,
            {'h': _balanceHours.toStringAsFixed(1)}),
        style: TextStyle(fontSize: 12, color: tk.ink3)));
    rows.add(const SizedBox(height: 6));
    rows.add(Text(AppStrings.t('sub_status_next', context),
        style: TextStyle(fontSize: 12, color: tk.ink2)));
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
              : (current ? tk.mint.withValues(alpha: 0.45) : tk.line),
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
          Text(AppStrings.tf('sub_hours_per_month', context, {'h': '$hours'}),
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: tk.ink)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: best
                ? ElevatedButton(
                    onPressed: (current || _busy) ? null : () => _buyTier(t),
                    child: Text(current
                        ? AppStrings.t('sub_current_badge', context)
                        : '${AppStrings.t('sub_buy', context)} · ${price ?? ''}'),
                  )
                : OutlinedButton(
                    onPressed: (current || _busy) ? null : () => _buyTier(t),
                    child: Text(current
                        ? AppStrings.t('sub_current_badge', context)
                        : AppStrings.t('sub_buy', context)),
                  ),
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
                        _purchases.priceOf(e.key) ??
                            AppStrings.t('sub_price_pending', context),
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
}
