// Task 065: СЌРєСЂР°РЅ В«РџРѕРґРїРёСЃРєР°В» вЂ” 3 С‚Р°СЂРёС„Р° (РњРµСЃСЏС†/Р“РѕРґ) + РїР°РєРµС‚С‹ РР-С‡Р°СЃРѕРІ.
//
// РЎРµСЂРІРёСЃ Рё С‚РѕРІР°СЂС‹ РіРѕС‚РѕРІС‹ СЂР°РЅСЊС€Рµ (054/059), UI Р±С‹Р» С‚РѕР»СЊРєРѕ РѕРґРёРЅ: РґРёР°Р»РѕРі
// В«Р»РёРјРёС‚ РёСЃС‡РµСЂРїР°РЅВ». Р—РґРµСЃСЊ РїРѕР»РЅРѕС†РµРЅРЅС‹Р№ СЌРєСЂР°РЅ: СЃС‚Р°С‚СѓСЃ, С‚Р°СЂРёС„С‹, РїР°РєРµС‚С‹,
// РІРѕСЃСЃС‚Р°РЅРѕРІР»РµРЅРёРµ, РїСЂРѕРјРѕРєРѕРґ. РўРѕРІР°СЂРѕРІ РІ РєРѕРЅСЃРѕР»СЏС… РїРѕРєР° РЅРµС‚ вЂ” СЌРєСЂР°РЅ РѕР±СЏР·Р°РЅ
// РѕС‚РєСЂС‹РІР°С‚СЊСЃСЏ Рё С‡РµСЃС‚РЅРѕ РѕР±СЉСЏСЃРЅСЏС‚СЊ СЃРѕСЃС‚РѕСЏРЅРёРµ, Р±РµР· РїСѓСЃС‚РѕС‚ Рё РїР°РґРµРЅРёР№.
import 'package:flutter/material.dart';

import 'app_strings.dart';
import 'services/ai_hours_service.dart';
import 'services/purchase_service.dart';

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

  /// Р¦РµРЅР° С‚РѕРІР°СЂР° РёР· СЃС‚РѕСЂР°; null вЂ” С‚РѕРІР°СЂР° РЅРµС‚ (РєРѕРЅСЃРѕР»СЊ РЅРµ РЅР°СЃС‚СЂРѕРµРЅР°).
  String? _priceOf(String productId) {
    for (final p in _purchases.products) {
      if (p.id == productId) return p.price;
    }
    return null;
  }

  String _tierProductId(SubscriptionTier t, {required bool yearly}) =>
      switch (t) {
        SubscriptionTier.diary =>
          yearly ? PurchaseService.subDiaryYearId : PurchaseService.subDiaryId,
        SubscriptionTier.assistant => yearly
            ? PurchaseService.subAssistantYearId
            : PurchaseService.subAssistantId,
        SubscriptionTier.unlimited => yearly
            ? PurchaseService.subUnlimitedYearId
            : PurchaseService.subUnlimitedId,
        SubscriptionTier.none => '',
      };

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

  Future<void> _restore() async {
    await _purchases.restore();
    await _refreshBalance();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.t('sub_purchased', context))),
      );
    }
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
      // Р‘СЌРєРµРЅРґР° РїСЂРѕРјРѕРєРѕРґРѕРІ РµС‰С‘ РЅРµС‚ вЂ” С‡РµСЃС‚РЅРѕ РіРѕРІРѕСЂРёРј, С‡С‚Рѕ Р±СѓРґРµС‚ РїРѕР·Р¶Рµ.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.t('sub_promo_pending', context))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.t('sub_title', context))),
      body: ValueListenableBuilder<SubscriptionTier>(
        valueListenable: _purchases.tier,
        builder: (context, tier, _) {
          return ValueListenableBuilder<bool>(
            valueListenable: _purchases.unlocked,
            builder: (context, unlocked, _) {
              final productsLoaded = _purchases.products.isNotEmpty;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
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
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 8),
                  _packsSection(context),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : _restore,
                          child: Text(AppStrings.t('sub_restore', context)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : _promo,
                          child: Text(AppStrings.t('sub_promo', context)),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _statusCard(BuildContext context, SubscriptionTier tier, bool unlocked) {
    final cs = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    if (tier == SubscriptionTier.none) {
      rows.add(Text(AppStrings.t('sub_status_none', context)));
    } else {
      rows.add(Text(
        AppStrings.tf('sub_status_tier', context, {'t': _tierName(context, tier)}),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ));
    }
    rows.add(const SizedBox(height: 6));
    rows.add(Text(AppStrings.tf('sub_status_balance', context,
        {'h': _balanceHours.toStringAsFixed(1)})));
    rows.add(const SizedBox(height: 6));
    rows.add(Text(
      AppStrings.t('sub_status_next', context),
      style: TextStyle(fontSize: 12, color: cs.secondary),
    ));
    if (unlocked) {
      rows.add(const SizedBox(height: 6));
      rows.add(Text(
        AppStrings.t('sub_full_unlock_status', context),
        style: TextStyle(fontSize: 12, color: Colors.green),
      ));
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        ),
      ),
    );
  }

  Widget _storeBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withOpacity(0.30)),
      ),
      child: Text(
        AppStrings.t('sub_store_banner', context),
        style: const TextStyle(fontSize: 12.5, color: Colors.amber),
      ),
    );
  }

  Widget _periodToggle(BuildContext context) {
    return SegmentedButton<bool>(
      segments: [
        ButtonSegment(
          value: false,
          label: Text(AppStrings.t('sub_period_month', context)),
        ),
        ButtonSegment(
          value: true,
          label: Text(AppStrings.t('sub_period_year', context)),
        ),
      ],
      selected: {_yearly},
      onSelectionChanged: _busy
          ? null
          : (s) => setState(() => _yearly = s.first),
    );
  }

  Widget _tierCard(BuildContext context, SubscriptionTier t,
      {required bool current}) {
    final cs = Theme.of(context).colorScheme;
    final productId = _tierProductId(t, yearly: _yearly);
    final price = _priceOf(productId);
    final periodHint =
        _yearly ? AppStrings.t('sub_year_hint', context) : AppStrings.t('sub_month_hint', context);
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: current
            ? BorderSide(color: cs.primary, width: 2)
            : BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _tierName(context, t),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                if (current)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      AppStrings.t('sub_current_badge', context),
                      style: TextStyle(fontSize: 11, color: cs.onPrimaryContainer),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(_tierDesc(context, t),
                style: TextStyle(fontSize: 13, color: cs.secondary)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: price != null
                      ? Text('$price / $periodHint',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600))
                      : Text(
                          AppStrings.t('sub_price_pending', context),
                          style:
                              TextStyle(fontSize: 12.5, color: cs.secondary),
                        ),
                ),
                FilledButton.tonal(
                  onPressed: (current || _busy) ? null : () => _buyTier(t),
                  child: Text(AppStrings.t('sub_buy', context)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _packsSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
          child: Text(
            AppStrings.t('sub_packs_title', context),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: cs.secondary,
            ),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final e in PurchaseService.packIds.entries) ...[
                ListTile(
                  leading: const Icon(Icons.bolt_outlined),
                  title: Text('${e.value.toStringAsFixed(0)} '
                      '${AppStrings.t('sub_packs_title', context).split(' ').first}'),
                  subtitle: Text(_priceOf(e.key) ??
                      AppStrings.t('sub_price_pending', context)),
                  trailing: FilledButton.tonal(
                    onPressed: _busy ? null : () => _buyPack(e.key),
                    child: Text(AppStrings.t('sub_buy_pack', context)),
                  ),
                ),
                if (e.key != PurchaseService.packIds.keys.last)
                  const Divider(height: 1),
              ],
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  AppStrings.t('sub_packs_note', context),
                  style: TextStyle(fontSize: 12, color: cs.secondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
