import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'services/ai_summary_service.dart';
import 'services/keep_alive.dart';
import 'services/stt_provider.dart';
import 'theme/app_theme.dart';

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
  bool _cloudSummary = false;
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
        SnackBar(content: Text(freed > 0 ? 'Освобождено $mb МБ' : 'Временных файлов нет')),
      );
    }
  }

  Future<void> _pickSttProvider() async {
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Провайдер онлайн-транскрипции'),
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
        title: Text('Ключ ${provider.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                'Ключ хранится только на устройстве. Без ключа онлайн-режим '
                'выключен — расшифровка идёт офлайн, на устройстве.',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Вставь API-ключ'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (res != null) {
      await SttSettings.setApiKey(provider.keyPrefsName, res);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(res.isEmpty ? 'Ключ удалён' : 'Ключ сохранён')));
      }
    }
  }

  Future<void> _editZaiKey() async {
    final current = await AiSummaryService.getApiKey();
    final ctrl = TextEditingController(text: current ?? '');
    if (!mounted) return;
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ключ Z.ai (ИИ-саммари)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Для ИИ-саммари записей. Ключ хранится только на устройстве. '
                'Без ключа используется офлайн-саммари.',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Вставь ключ Z.ai'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (res != null) {
      await AiSummaryService.setApiKey(res);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(res.isEmpty
                ? 'Ключ удалён — офлайн-саммари'
                : 'Ключ сохранён — ИИ-саммари включено')));
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
    final cloudSummary = await AiSummaryService.cloudEnabled();
    if (mounted) setState(() => _cloudSummary = cloudSummary);
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
        title: const Text('Настройки'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () async {
              await _saveSettings();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Сохранено')),
                );
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _group(context, 'Оформление', [
            SwitchListTile(
              secondary: const Icon(Icons.brightness_6_outlined),
              title: const Text('Светлая тема'),
              subtitle: const Text('Дневное оформление приложения'),
              value: ThemeController.instance.isLight,
              onChanged: (v) async {
                await ThemeController.instance
                    .setTheme(v ? ThemeMode.light : ThemeMode.dark);
                if (mounted) setState(() {});
              },
            ),
          ]),
          _group(context, 'Запись', [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDropdown(
                    label: 'Частота дискретизации (Hz)',
                    value: _settings.sampleRate,
                    items: _sampleRates,
                    onChanged: (val) => setState(() => _settings.sampleRate = val!),
                  ),
                  const SizedBox(height: 14),
                  _buildDropdown(
                    label: 'Битрейт (bps)',
                    value: _settings.bitRate,
                    items: _bitRates,
                    onChanged: (val) => setState(() => _settings.bitRate = val!),
                  ),
                  const SizedBox(height: 14),
                  _buildDropdown(
                    label: 'Каналы',
                    value: _settings.numChannels,
                    items: const [1, 2],
                    itemLabel: (v) => v == 1 ? 'Моно (1)' : 'Стерео (2)',
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
                child: const Text(
                  'Высокие настройки улучшают качество, но увеличивают размер файла. '
                  'Для расшифровки достаточно 16 кГц, моно.',
                  style: TextStyle(fontSize: 12.5, color: Colors.amber),
                ),
              ),
            ),
          ]),
          _group(context, 'Распознавание', [
            const ListTile(
              leading: Icon(Icons.auto_awesome),
              title: Text('Движок: на устройстве, модель внутри'),
              subtitle: Text('Точная модель GigaAM работает локально. '
                  'Интернет не нужен, файлы не покидают телефон.'),
            ),
            const Divider(height: 1),
            SwitchListTile(
              secondary: const Icon(Icons.cloud_upload_outlined),
              title: const Text('Онлайн-расшифровка'),
              subtitle: const Text('Точнее локальной модели, но звук уходит на сервер провайдера'),
              value: _sttEnabled,
              onChanged: (v) async {
                await SttSettings.setEnabled(v);
                if (mounted) setState(() => _sttEnabled = v);
              },
            ),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('Провайдер'),
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
          _group(context, 'Саммари', [
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('ИИ-саммари (Z.ai)'),
              subtitle: const Text('Ключ для умных саммари; без ключа — офлайн'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _editZaiKey,
            ),
            const Divider(height: 1),
            SwitchListTile(
              secondary: const Icon(Icons.summarize_outlined),
              title: const Text('Облачное саммари (Z.ai)'),
              subtitle: const Text('Выкл. = саммари на устройстве. Вкл. = текст записи уходит в Z.ai'),
              value: _cloudSummary,
              onChanged: (v) async {
                await AiSummaryService.setCloudEnabled(v);
                if (mounted) setState(() => _cloudSummary = v);
              },
            ),
          ]),
          _group(context, 'Фон и память', [
            // Задача 036: MIUI убивает фоновые процессы без исключения —
            // без этого длинная расшифровка с выключенным экраном нежизнеспособна.
            // Задача 038: после системного запроса показываем ФАКТИЧЕСКОЕ
            // состояние (MIUI-диалог выбора не говорит, включилось ли) и даём
            // прямой выход на экран батареи приложения.
            ListTile(
              leading: const Icon(Icons.battery_saver_outlined),
              title: const Text('Работа без ограничений (MIUI)'),
              subtitle: Text(
                'Запросить исключение из оптимизации батареи. Без него '
                'система может остановить длинную расшифровку в фоне.\n'
                'Работа без ограничений: '
                '${_batteryUnrestricted == null ? 'проверяю…' : (_batteryUnrestricted! ? 'включено' : 'не включено')}'
                '${_batteryUnrestricted == false ? '\nMIUI: Сведения о батарее → Без ограничений' : ''}',
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
                    child: const Text('Включить'),
                  ),
                  if (_batteryUnrestricted == false)
                    TextButton(
                      onPressed: () async {
                        await TranscribeKeepAlive.openBatterySettings();
                        await Future.delayed(const Duration(seconds: 1));
                        await _refreshBatteryStatus();
                      },
                      child: const Text('Открыть настройки батареи'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('Временные файлы'),
              subtitle: Text(_tempBytes > 0
                  ? 'Занято: ${(_tempBytes / 1024 / 1024).toStringAsFixed(1)} МБ. Обычно мусор удаляется сразу после расшифровки.'
                  : 'Временных файлов нет — мусор удаляется сразу после расшифровки.'),
              trailing: TextButton(
                onPressed: _tempBytes > 0 ? _clearTempNow : null,
                child: const Text('Очистить'),
              ),
            ),
          ]),
          _group(context, 'Данные', [
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
