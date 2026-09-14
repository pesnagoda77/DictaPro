import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'services/ai_summary_service.dart';

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
