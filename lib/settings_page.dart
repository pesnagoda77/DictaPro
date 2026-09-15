import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'services/ai_summary_service.dart';
import 'services/stt_provider.dart';
import 'services/gigaam_service.dart';
import 'services/local_text_cleanup.dart';

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
  }

  bool _sttEnabled = false;
  bool _cloudSummary = false;
  bool _cleanupEnabled = true;
  String _engine = 'vosk';
  bool _gigaamReady = false;
  bool _downloading = false;
  int _dlReceived = 0;
  int _dlTotal = 1;
  String _sttProviderTitle = 'Groq (whisper-large-v3-turbo)';

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
                'выключен (работает офлайн VOSK).',
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
          ListTile(
            leading: const Icon(Icons.auto_awesome),
            title: const Text('ИИ-саммари (Z.ai)'),
            subtitle: const Text('Ключ для умных саммари; без ключа — офлайн'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _editZaiKey,
          ),
          const Divider(),
          SwitchListTile(
            secondary: const Icon(Icons.summarize_outlined),
            title: const Text('Облачное саммари (Z.ai)'),
            subtitle: const Text(
                'ВЫКЛ = саммари делается локально на устройстве. ВКЛ = текст записи отправляется в Z.ai'),
            value: _cloudSummary,
            onChanged: (v) async {
              await AiSummaryService.setCloudEnabled(v);
              if (mounted) setState(() => _cloudSummary = v);
            },
          ),
          const Divider(),
          SwitchListTile(
            secondary: const Icon(Icons.cloud_upload_outlined),
            title: const Text('Онлайн-транскрипция'),
            subtitle: const Text(
                'Точнее VOSK. Звук уходит на сервер провайдера (мягкое предупреждение перед первым разом)'),
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
    // Реальное состояние модели (не только текущая сессия):
    // иначе после перезапуска снова показываем «Скачать модель», вводя в заблуждение.
    final gigaamReady = await GigaamService.isModelDownloaded();
    if (mounted) setState(() => _gigaamReady = gigaamReady);
    final sttEnabled = await SttSettings.isEnabled();
    final prov = SttProvider.byId(await SttSettings.providerId());
    final cleanupEnabled = await LocalTextCleanupSettings.isEnabled();
    if (mounted) {
      setState(() {
        _sttEnabled = sttEnabled;
        _sttProviderTitle = prov.title;
        _cleanupEnabled = cleanupEnabled;
      });
    }
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
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Качество записи',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildDropdown(
            label: 'Частота дискретизации (Hz)',
            value: _settings.sampleRate,
            items: _sampleRates,
            onChanged: (val) => setState(() => _settings.sampleRate = val!),
          ),
          const SizedBox(height: 16),
          _buildDropdown(
            label: 'Битрейт (bps)',
            value: _settings.bitRate,
            items: _bitRates,
            onChanged: (val) => setState(() => _settings.bitRate = val!),
          ),
          const SizedBox(height: 16),
          _buildDropdown(
            label: 'Каналы',
            value: _settings.numChannels,
            items: const [1, 2],
            itemLabel: (v) => v == 1 ? 'Моно (1)' : 'Стерео (2)',
            onChanged: (val) => setState(() => _settings.numChannels = val!),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withOpacity(0.3)),
            ),
            child: const Text(
              'Высокие настройки улучшают качество, но увеличивают размер файла. '
              'Для транскрибации достаточно 16kHz моно.',
              style: TextStyle(fontSize: 12, color: Colors.amber),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Транскрипция',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          RadioListTile<String>(
            secondary: const Icon(Icons.graphic_eq),
            title: const Text('VOSK (текущий)'),
            subtitle: const Text('Быстрый, лёгкий. Движок по умолчанию.'),
            value: 'vosk',
            groupValue: _engine,
            onChanged: (v) async {
              await GigaamService.setEngine(v!);
              if (mounted) setState(() => _engine = v);
            },
          ),
          RadioListTile<String>(
            secondary: const Icon(Icons.auto_awesome),
            title: const Text('GigaAM (эксперимент)'),
            subtitle: Text(_gigaamReady
                ? 'Модель скачана. Русский ~в 6 раз точнее VOSK, пунктуация из коробки.'
                : 'Модель ~230 МБ — скачать по Wi-Fi'),
            value: 'gigaam',
            groupValue: _engine,
            onChanged: (v) async {
              await GigaamService.setEngine(v!);
              if (mounted) setState(() => _engine = v);
            },
          ),
          if (_engine == 'gigaam' && !_gigaamReady) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _downloading
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(
                          value: _dlReceived / _dlTotal.clamp(1, _dlTotal),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${(_dlReceived / 1048576).toStringAsFixed(0)} из ~233 МБ',
                          style: const TextStyle(fontSize: 12, color: Colors.white54),
                        ),
                      ],
                    )
                  : ElevatedButton.icon(
                      onPressed: () async {
                        setState(() {
                          _downloading = true;
                          _dlReceived = 0;
                          _dlTotal = 233 * 1048576;
                        });
                        bool ok = false;
                        try {
                          ok = await GigaamService.downloadModel((r, t, f) {
                            if (mounted) {
                              setState(() {
                                _dlReceived = r;
                                _dlTotal = t;
                              });
                            }
                          });
                        } catch (e) {
                          debugPrint('[gigaam] download error: $e');
                        }
                        if (mounted) {
                          setState(() {
                            _downloading = false;
                            _gigaamReady = ok;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(ok
                                ? 'Модель GigaAM готова'
                                : 'Ошибка скачивания — проверь сеть'),
                          ));
                        }
                      },
                      icon: const Icon(Icons.download),
                      label: const Text('Скачать модель GigaAM (~230 МБ)'),
                    ),
            ),
            const SizedBox(height: 8),
          ],
          SwitchListTile(
            secondary: const Icon(Icons.tune),
            title: const Text('Локальная чистка текста'),
            subtitle: const Text(
                'Числа цифрами, пробелы и пунктуация после офлайн-распознавания. '
                'Полностью на устройстве, без сети.'),
            value: _cleanupEnabled,
            onChanged: (v) async {
              await LocalTextCleanupSettings.setEnabled(v);
              if (mounted) setState(() => _cleanupEnabled = v);
            },
          ),
        ],
      ),
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
        Text(label, style: const TextStyle(fontSize: 14, color: Colors.white70)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              dropdownColor: const Color(0xFF1E1E2E),
              style: const TextStyle(color: Colors.white),
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
