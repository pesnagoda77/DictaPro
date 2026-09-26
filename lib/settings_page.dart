import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'services/keep_alive.dart';
import 'services/purchase_service.dart';
import 'services/stt_provider.dart';
import 'subscription_page.dart';
import 'theme/app_theme.dart';
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
        title: Text(AppStrings.t('provider_dialog_title', context)),
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
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.tf('key_for', context, {'p': provider.title})),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                AppStrings.t('key_dialog_body', context),
                style: TextStyle(fontSize: 12, color: Colors.white70)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: true,
              decoration: InputDecoration(labelText: AppStrings.t('paste_api_key', context)),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(AppStrings.t('long_transcribe_cancel', context))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(AppStrings.t('save', context)),
          ),
        ],
      ),
    );
    if (res != null) {
      await SttSettings.setApiKey(provider.keyPrefsName, res);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(res.isEmpty ? AppStrings.t('key_removed', context) : AppStrings.t('key_saved', context))));
      }
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

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.t('settings_title', context)),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () async {
              await _saveSettings();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(AppStrings.t('saved', context))),
                );
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _group(context, AppStrings.t('group_appearance', context), [
            SwitchListTile(
              secondary: const Icon(Icons.brightness_6_outlined),
              title: Text(AppStrings.t('light_theme', context)),
              subtitle: Text(AppStrings.t('light_theme_sub', context)),
              value: ThemeController.instance.isLight,
              onChanged: (v) async {
                await ThemeController.instance
                    .setTheme(v ? ThemeMode.light : ThemeMode.dark);
                if (mounted) setState(() {});
              },
            ),
          ]),
          // Task 065: вход на экран «Подписка» — виден всегда, а не только
          // при исчерпании лимита.
          _group(context, AppStrings.t('sub_title', context), [
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
                return ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined),
                  title: Text(AppStrings.t('sub_settings_sub', context)),
                  subtitle: Text(subtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const SubscriptionPage()),
                  ),
                );
              },
            ),
          ]),
          _group(context, AppStrings.t('group_recording', context), [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDropdown(
                    label: AppStrings.t('sample_rate', context),
                    value: _settings.sampleRate,
                    items: _sampleRates,
                    onChanged: (val) => setState(() => _settings.sampleRate = val!),
                  ),
                  const SizedBox(height: 14),
                  _buildDropdown(
                    label: AppStrings.t('bitrate', context),
                    value: _settings.bitRate,
                    items: _bitRates,
                    onChanged: (val) => setState(() => _settings.bitRate = val!),
                  ),
                  const SizedBox(height: 14),
                  _buildDropdown(
                    label: AppStrings.t('channels', context),
                    value: _settings.numChannels,
                    items: const [1, 2],
                    itemLabel: (v) => v == 1 ? AppStrings.t('mono', context) : AppStrings.t('stereo', context),
                    onChanged: (val) => setState(() => _settings.numChannels = val!),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.withOpacity(0.30)),
                ),
                child: Text(
                  AppStrings.t('quality_note', context),
                  style: TextStyle(fontSize: 12.5, color: Colors.amber),
                ),
              ),
            ),
          ]),
          _group(context, AppStrings.t('group_recognition', context), [
            ListTile(
              leading: Icon(Icons.auto_awesome),
              title: Text(AppStrings.t('engine_on_device', context)),
              subtitle: Text(AppStrings.t('engine_on_device_sub', context)),
            ),
            const Divider(height: 1),
            SwitchListTile(
              secondary: const Icon(Icons.cloud_upload_outlined),
              title: Text(AppStrings.t('online_transcribe', context)),
              subtitle: Text(AppStrings.t('online_transcribe_sub', context)),
              value: _sttEnabled,
              onChanged: (v) async {
                await SttSettings.setEnabled(v);
                if (mounted) setState(() => _sttEnabled = v);
              },
            ),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(AppStrings.t('provider', context)),
              subtitle: Text(_sttProviderTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickSttProvider,
            ),
            for (final pr in SttProvider.all)
              ListTile(
                leading: const Icon(Icons.vpn_key_outlined),
                title: Text('Ключ ${pr.title}'),
                subtitle: const Text('Хранится только на устройстве'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _editSttKey(pr),
              ),
          ]),
          _group(context, AppStrings.t('group_background', context), [
            // Задача 036: MIUI убивает фоновые процессы без исключения —
            // без этого длинная расшифровка с выключенным экраном нежизнеспособна.
            // Задача 038: после системного запроса показываем ФАКТИЧЕСКОЕ
            // состояние (MIUI-диалог выбора не говорит, включилось ли) и даём
            // прямой выход на экран батареи приложения.
            ListTile(
              leading: const Icon(Icons.battery_saver_outlined),
              title: Text(AppStrings.t('miui_unrestricted', context)),
              subtitle: Text(
                AppStrings.tf('miui_sub', context, {
                  's': _batteryUnrestricted == null
                      ? AppStrings.t('miui_checking', context)
                      : (_batteryUnrestricted! ? AppStrings.t('miui_on', context) : AppStrings.t('miui_off', context)),
                }) +
                (_batteryUnrestricted == false ? '\n${AppStrings.t('miui_manual_path', context)}' : ''),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FilledButton.tonal(
                    onPressed: () async {
                      await TranscribeKeepAlive.requestBatteryUnrestricted();
                      // Пользователь ходил в системный экран — проверяем факт.
                      await Future.delayed(const Duration(seconds: 1));
                      await _refreshBatteryStatus();
                    },
                    child: Text(AppStrings.t('enable', context)),
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
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: Text(AppStrings.t('temp_files', context)),
              subtitle: Text(_tempBytes > 0
                  ? AppStrings.tf('temp_occupied', context, {'m': '${(_tempBytes / 1024 / 1024).toStringAsFixed(1)}'})
                  : AppStrings.t('temp_none', context)),
              trailing: TextButton(
                onPressed: _tempBytes > 0 ? _clearTempNow : null,
                child: Text(AppStrings.t('clear', context)),
              ),
            ),
          ]),
          _group(context, AppStrings.t('group_data', context), [
            const ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('Всё хранится на устройстве'),
              subtitle: Text('Записи, тексты и ключи не покидают телефон без вашего решения.'),
            ),
            const Divider(height: 1),
            const ListTile(
              leading: Icon(Icons.folder_outlined),
              title: Text('Папка обмена (диагностика)'),
              subtitle: Text('Android/data/com.dictapro.app/files — тексты и временные WAV для проверки'),
            ),
          ]),
        ],
      ),
    );
  }

  /// Группа настроек: заголовок + карточка с содержимым.
  Widget _group(BuildContext context, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 18, 6, 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
    String Function(T)? itemLabel,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey,
            )),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.45),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              dropdownColor: Theme.of(context).colorScheme.surface,
              style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
              items: items.map((item) {
                final label = itemLabel != null ? itemLabel(item) : item.toString();
                return DropdownMenuItem<T>(
                  value: item,
                  child: Text(label),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
