import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'services/keep_alive.dart';
import 'services/purchase_service.dart';
import 'services/stt_provider.dart';
import 'subscription_page.dart';
import 'theme/app_theme.dart';
import 'locale_controller.dart';
import 'app_strings.dart';

class RecorderSettings {
  static const String boxName = 'settings';

  int sampleRate;
  int bitRate;
  int numChannels;

  RecorderSettings({
    this.sampleRate = 44100,
    this.bitRate = 128000,
    this.numChannels = 1,
  });

  Map<String, dynamic> toMap() => {
        'sampleRate': sampleRate,
        'bitRate': bitRate,
        'numChannels': numChannels,
      };

  factory RecorderSettings.fromMap(Map<String, dynamic> map) => RecorderSettings(
        sampleRate: map['sampleRate'] ?? 44100,
        bitRate: map['bitRate'] ?? 128000,
        numChannels: map['numChannels'] ?? 1,
      );
}

/// Задача 068: экран «Настройки» в стиле V3 (экран 13 макета) — группы с
/// мятными капс-заголовками 10.5/700, строки-разделители с тонкой линией,
/// моно-значения, мятные переключатели. Фон — DictaBackground.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late RecorderSettings _settings;
  bool _loaded = false;

  final _sampleRates = [16000, 22050, 44100, 48000];
  final _bitRates = [64000, 128000, 192000, 256000, 320000];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _refreshBatteryStatus();
  }

  bool _sttEnabled = false;
  String _sttProviderTitle = 'Groq (whisper-large-v3-turbo)';
  String _asrLang = 'ru';
  String _uiLang = 'system';
  int _tempBytes = 0;

  // Задача 038: фактическое состояние исключения из экономии батареи.
  // null — Android не ответил; обновляем при входе и после запроса.
  bool? _batteryUnrestricted;

  Future<void> _refreshBatteryStatus() async {
    final v = await TranscribeKeepAlive.batteryUnrestricted();
    if (mounted) setState(() => _batteryUnrestricted = v);
  }

  // Задача 036: показываем занятое временными файлами место и даём
  // чистить вручную (основной сценарий — автоочистка сразу после операции).
  Future<void> _refreshTempSize() async {
    final n = await TranscribeKeepAlive.tempSize();
    if (mounted) setState(() => _tempBytes = n);
  }

  Future<void> _clearTempNow() async {
    final freed = await TranscribeKeepAlive.cleanupTempFiles();
    await _refreshTempSize();
    if (mounted) {
      final mb = (freed / 1024 / 1024).toStringAsFixed(1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(freed > 0 ? AppStrings.tf('freed_mb', context, {'m': mb}) : AppStrings.t('temp_none', context))),
      );
    }
  }

  Future<void> _pickSttProvider() async {
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(AppStrings.t('provider_dialog_title', ctx)),
        children: [
          for (final pr in SttProvider.all)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, pr.id),
              child: Text(pr.title),
            ),
        ],
      ),
    );
    if (id != null) {
      await SttSettings.setProviderId(id);
      if (mounted) {
        setState(() => _sttProviderTitle = SttProvider.byId(id).title);
      }
    }
  }

  Future<void> _editSttKey(SttProvider provider) async {
    final current = await SttSettings.apiKey(provider.keyPrefsName);
    final ctrl = TextEditingController(text: current ?? '');
    if (!mounted) return;
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final tk = DictaTokens.of(ctx);
        return AlertDialog(
          title: Text(AppStrings.tf('key_for', ctx, {'p': provider.title})),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppStrings.t('key_dialog_body', ctx),
                style: TextStyle(fontSize: 12, color: tk.ink2),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                obscureText: true,
                decoration: InputDecoration(labelText: AppStrings.t('paste_api_key', ctx)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppStrings.t('long_transcribe_cancel', ctx)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(AppStrings.t('save', ctx)),
            ),
          ],
        );
      },
    );
    if (res != null) {
      await SttSettings.setApiKey(provider.keyPrefsName, res);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(res.isEmpty ? AppStrings.t('key_removed', context) : AppStrings.t('key_saved', context))));
      }
    }
  }

  String get _asrLangTitle => switch (_asrLang) {
        'en' => 'English',
        'de' => 'Deutsch',
        'fr' => 'Français',
        'es' => 'Español',
        'it' => 'Italiano',
        _ => 'Русский',
      };

  String _uiLangTitle(BuildContext context) => switch (_uiLang) {
        'ru' => 'Русский',
        'en' => 'English',
        'de' => 'Deutsch',
        'fr' => 'Français',
        'es' => 'Español',
        'it' => 'Italiano',
        _ => AppStrings.t('ui_lang_system', context),
      };

  Future<void> _pickUiLang() async {
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(AppStrings.t('ui_lang_title', ctx)),
        children: [
          for (final e in [
            ('system', AppStrings.t('ui_lang_system', ctx)),
            ('ru', 'Русский'),
            ('en', 'English'),
            ('de', 'Deutsch'),
            ('fr', 'Français'),
            ('es', 'Español'),
            ('it', 'Italiano'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, e.$1),
              child: Row(children: [
                Icon(
                  _uiLang == e.$1
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 18,
                  color: DictaTokens.of(context).mint,
                ),
                const SizedBox(width: 10),
                Text(e.$2),
              ]),
            ),
        ],
      ),
    );
    if (res == null) return;
    await LocaleController.instance.setLang(res);
    if (mounted) setState(() => _uiLang = res);
  }

  Future<void> _pickAsrLang() async {
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(AppStrings.t('asr_lang_title', ctx)),
        children: [
          for (final e in [
            ('ru', 'Русский', AppStrings.t('asr_gigaam_offline', ctx)),
            ('en', 'English', AppStrings.t('asr_whisper_offline', ctx)),
            ('de', 'Deutsch', AppStrings.t('asr_whisper_offline', ctx)),
            ('fr', 'Français', AppStrings.t('asr_whisper_offline', ctx)),
            ('es', 'Español', AppStrings.t('asr_whisper_offline', ctx)),
            ('it', 'Italiano', AppStrings.t('asr_whisper_offline', ctx)),
          ])
            RadioListTile<String>(
              value: e.$1,
              groupValue: _asrLang,
              title: Text(e.$2),
              subtitle: Text(e.$3),
              onChanged: (v) => Navigator.pop(ctx, v),
            ),
        ],
      ),
    );
    if (res == null) return;
    try {
      final sbox = await Hive.openBox<dynamic>('settings');
      await sbox.put('asr_lang', res);
    } catch (_) {}
    if (mounted) {
      setState(() => _asrLang = res);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.t('asr_lang_saved', context))),
      );
    }
  }

  Future<void> _loadSettings() async {
    final box = await Hive.openBox<dynamic>(RecorderSettings.boxName);
    final raw = box.get('recorder');
    setState(() {
      _settings = raw != null
          ? RecorderSettings.fromMap(Map<String, dynamic>.from(raw))
          : RecorderSettings();
      _loaded = true;
    });
    try {
      final sbox = await Hive.openBox<dynamic>('settings');
      final lang = (sbox.get('asr_lang') ?? AppStrings.defaultAsrLang()).toString();
      final ui = (sbox.get('ui_lang') ?? 'system').toString();
      if (mounted) setState(() {
        _asrLang = lang;
        _uiLang = ui;
      });
    } catch (_) {}
    final sttEnabled = await SttSettings.isEnabled();
    final prov = SttProvider.byId(await SttSettings.providerId());
    if (mounted) {
      setState(() {
        _sttEnabled = sttEnabled;
        _sttProviderTitle = prov.title;
      });
    }
    await _refreshTempSize();
  }

  Future<void> _saveSettings() async {
    final box = await Hive.openBox<dynamic>(RecorderSettings.boxName);
    await box.put('recorder', _settings.toMap());
  }

  Future<void> _saveAndNotify() async {
    await _saveSettings();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.t('saved', context))),
      );
    }
  }

  // ── Моно-значения (цифры — JetBrains Mono, экран 13 макета) ─────────────

  static String _groupDigits(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return b.toString();
  }

  static String _fmtSampleRate(int v) =>
      '${_groupDigits(v)} ${AppStrings.tGlobal('unit_hz')}';

  static String _fmtBitrate(int v) => '${v ~/ 1000} kbps';

  @override
  Widget build(BuildContext context) {
    final tk = DictaTokens.of(context);
    return Scaffold(
      body: DictaBackground(
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded, size: 20),
                      ),
                      Text(AppStrings.t('settings_title', context),
                          style: Theme.of(context).textTheme.headlineMedium),
                      const Spacer(),
                      IconButton(
                        tooltip: AppStrings.t('save', context),
                        onPressed: _saveAndNotify,
                        icon: Icon(Icons.save_rounded, size: 20, color: tk.mint),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // ── Оформление ────────────────────────────────────────
                  _groupTitle(context, AppStrings.t('group_appearance', context)),
                  _tile(
                    context,
                    title: AppStrings.t('ui_lang_title', context),
                    sub: _uiLangTitle(context),
                    trailing: _chevron(context),
                    onTap: _pickUiLang,
                  ),
                  _tile(
                    context,
                    title: AppStrings.t('light_theme', context),
                    sub: AppStrings.t('light_theme_sub', context),
                    trailing: Switch(
                      value: ThemeController.instance.isLight,
                      onChanged: (v) async {
                        await ThemeController.instance
                            .setTheme(v ? ThemeMode.light : ThemeMode.dark);
                        if (mounted) setState(() {});
                      },
                    ),
                  ),

                  // ── Запись ────────────────────────────────────────────
                  _groupTitle(context, AppStrings.t('group_recording', context)),
                  _choiceTile<int>(
                    context,
                    title: AppStrings.t('sample_rate_label', context),
                    value: _settings.sampleRate,
                    items: _sampleRates,
                    labelOf: _fmtSampleRate,
                    onChanged: (v) => setState(() => _settings.sampleRate = v),
                  ),
                  _choiceTile<int>(
                    context,
                    title: AppStrings.t('bitrate_label', context),
                    value: _settings.bitRate,
                    items: _bitRates,
                    labelOf: _fmtBitrate,
                    onChanged: (v) => setState(() => _settings.bitRate = v),
                  ),
                  _choiceTile<int>(
                    context,
                    title: AppStrings.t('channels', context),
                    value: _settings.numChannels,
                    items: const [1, 2],
                    labelOf: (v) =>
                        v == 1 ? AppStrings.t('mono', context) : AppStrings.t('stereo', context),
                    onChanged: (v) => setState(() => _settings.numChannels = v),
                  ),
                  _notePlate(context, AppStrings.t('quality_note', context)),

                  // ── Распознавание ─────────────────────────────────────
                  _groupTitle(context, AppStrings.t('group_recognition', context)),
                  _tile(
                    context,
                    title: AppStrings.t('engine_on_device', context),
                    sub: AppStrings.t('engine_on_device_sub', context),
                  ),
                  _tile(
                    context,
                    title: AppStrings.t('asr_lang_title', context),
                    sub: _asrLangTitle,
                    trailing: _chevron(context),
                    onTap: _pickAsrLang,
                  ),
                  _tile(
                    context,
                    title: AppStrings.t('online_transcribe', context),
                    sub: AppStrings.t('online_transcribe_sub', context),
                    trailing: Switch(
                      value: _sttEnabled,
                      onChanged: (v) async {
                        await SttSettings.setEnabled(v);
                        if (mounted) setState(() => _sttEnabled = v);
                      },
                    ),
                  ),
                  _tile(
                    context,
                    title: AppStrings.t('provider', context),
                    sub: _sttProviderTitle,
                    trailing: _chevron(context),
                    onTap: _pickSttProvider,
                  ),
                  for (final pr in SttProvider.all)
                    _tile(
                      context,
                      title: AppStrings.tf('key_for', context, {'p': pr.title}),
                      sub: AppStrings.t('key_stored_local', context),
                      trailing: _chevron(context),
                      onTap: () => _editSttKey(pr),
                    ),

                  // ── Фон и память ──────────────────────────────────────
                  _groupTitle(context, AppStrings.t('group_background', context)),
                  _miuiTile(context),
                  _tempTile(context),

                  // ── Данные ────────────────────────────────────────────
                  _groupTitle(context, AppStrings.t('group_data', context)),
                  _tile(
                    context,
                    title: AppStrings.t('all_on_device', context),
                    sub: AppStrings.t('all_on_device_sub', context),
                  ),
                  _tile(
                    context,
                    title: AppStrings.t('share_folder_diag', context),
                    sub: AppStrings.t('share_folder_sub', context),
                  ),

                  // ── Подписка и ИИ-часы (вход в раздел) ────────────────
                  ValueListenableBuilder<SubscriptionTier>(
                    valueListenable: PurchaseService.instance.tier,
                    builder: (context, tier, _) {
                      final subtitle = tier == SubscriptionTier.none
                          ? AppStrings.t('sub_status_none', context)
                          : AppStrings.tf('sub_status_tier', context, {
                              't': switch (tier) {
                                SubscriptionTier.diary =>
                                  AppStrings.t('sub_tier_diary', context),
                                SubscriptionTier.assistant =>
                                  AppStrings.t('sub_tier_assistant', context),
                                SubscriptionTier.unlimited =>
                                  AppStrings.t('sub_tier_unlimited', context),
                                SubscriptionTier.none => '',
                              },
                            });
                      return _tile(
                        context,
                        title: AppStrings.t('sub_row_title', context),
                        sub: subtitle,
                        trailing: _chevron(context),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const SubscriptionPage()),
                        ),
                        last: true,
                      );
                    },
                  ),
                ],
              ),
      ),
    );
  }

  // ── Элементы в стиле V3 (экран 13 макета) ───────────────────────────────

  /// Заголовок группы: мята, капс, 10.5/700 (аналог .grp).
  Widget _groupTitle(BuildContext context, String title) {
    final tk = DictaTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 2),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: tk.mint,
        ),
      ),
    );
  }

  /// Строка-разделитель: тонкая линия tk.line, заголовок 12.5/600 + подпись.
  Widget _tile(
    BuildContext context, {
    required String title,
    String? sub,
    Widget? trailing,
    VoidCallback? onTap,
    bool last = false,
  }) {
    final tk = DictaTokens.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: tk.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600)),
                  if (sub != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(sub,
                          style: TextStyle(
                              fontSize: 11, color: tk.ink3, height: 1.35)),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              trailing,
            ],
          ],
        ),
      ),
    );
  }

  /// Строка-выбор: значение моно-шрифтом, справа раскрывающийся список.
  Widget _choiceTile<T>(
    BuildContext context, {
    required String title,
    required T value,
    required List<T> items,
    required String Function(T) labelOf,
    required ValueChanged<T> onChanged,
  }) {
    final tk = DictaTokens.of(context);
    final valueStyle = tk.mono(12, FontWeight.w600);
    return _tile(
      context,
      title: title,
      trailing: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          borderRadius: BorderRadius.circular(10),
          dropdownColor: tk.surface2,
          icon: Icon(Icons.expand_more_rounded, size: 18, color: tk.ink3),
          style: valueStyle,
          items: [
            for (final it in items)
              DropdownMenuItem<T>(
                value: it,
                child: Text(labelOf(it), style: valueStyle),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  /// Плашка-примечание: тонкая мятная рамка (аналог .note-r).
  Widget _notePlate(BuildContext context, String text) {
    final tk = DictaTokens.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tk.mint.withValues(alpha: 0.30)),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 11.5, color: tk.ink2, height: 1.5)),
    );
  }

  /// Стрелка перехода в строках-ссылках.
  Widget _chevron(BuildContext context) => Icon(
        Icons.chevron_right_rounded,
        size: 19,
        color: DictaTokens.of(context).ink3,
      );

  /// Компактная капсула-кнопка (радиус 99) для действий в строке.
  Widget _pillButton(
    BuildContext context,
    String text, {
    VoidCallback? onTap,
    bool accent = true,
  }) {
    final tk = DictaTokens.of(context);
    final enabled = onTap != null;
    final Color fg = !enabled ? tk.ink3 : (accent ? tk.mint : tk.ink2);
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: accent
              ? tk.mint.withValues(alpha: enabled ? 0.13 : 0.05)
              : null,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: accent
                ? tk.mint.withValues(alpha: enabled ? 0.30 : 0.15)
                : tk.line,
          ),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
      ),
    );
  }

  /// MIUI «Работа без ограничений»: фактический статус + кнопки запроса.
  Widget _miuiTile(BuildContext context) {
    final tk = DictaTokens.of(context);
    final String status = _batteryUnrestricted == null
        ? AppStrings.t('miui_checking', context)
        : (_batteryUnrestricted!
            ? AppStrings.t('miui_on', context)
            : AppStrings.t('miui_off', context));
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tk.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppStrings.t('miui_unrestricted', context),
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(status,
                    style:
                        TextStyle(fontSize: 11, color: tk.ink3, height: 1.35)),
                if (_batteryUnrestricted == false)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(AppStrings.t('miui_manual_path', context),
                        style: TextStyle(
                            fontSize: 11, color: tk.ink3, height: 1.35)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _pillButton(
                context,
                AppStrings.t('enable', context),
                onTap: () async {
                  await TranscribeKeepAlive.requestBatteryUnrestricted();
                  // Пользователь ходил в системный экран — проверяем факт.
                  await Future.delayed(const Duration(seconds: 1));
                  await _refreshBatteryStatus();
                },
              ),
              if (_batteryUnrestricted == false)
                TextButton(
                  onPressed: () async {
                    await TranscribeKeepAlive.openBatterySettings();
                    await Future.delayed(const Duration(seconds: 1));
                    await _refreshBatteryStatus();
                  },
                  child: Text(AppStrings.t('open_battery_settings', context)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// «Временные файлы»: занятое место + ручная очистка.
  Widget _tempTile(BuildContext context) {
    final tk = DictaTokens.of(context);
    final String subText = _tempBytes > 0
        ? AppStrings.tf('temp_occupied', context, {
            'm': (_tempBytes / 1024 / 1024).toStringAsFixed(1),
          })
        : AppStrings.t('temp_none', context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tk.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppStrings.t('temp_files', context),
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subText,
                    style:
                        TextStyle(fontSize: 11, color: tk.ink3, height: 1.35)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _pillButton(
            context,
            AppStrings.t('clear', context),
            onTap: _tempBytes > 0 ? _clearTempNow : null,
            accent: false,
          ),
        ],
      ),
    );
  }
}
