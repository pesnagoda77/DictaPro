import 'dart:io';

// Task 116 (Славан): экран «Папка записей» — единый на обеих платформах.
// Список файлов: Android — MediaStore, iOS — файловая система.
// Тап по файлу → он появляется в списке на главной (если его там нет)
// и происходит переход на главную.
// Task 117: полный абсолютный путь (тап — копировать), кнопка «Открыть
// в проводнике», синхронизация внешних переименований, переход на главную
// с прокруткой и подсветкой записи.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'app_strings.dart';
import 'audio_service.dart';
import 'main_shell.dart';
import 'services/audio_normalizer.dart';
import 'theme/app_theme.dart';
import 'widgets/dicta_ui.dart';

class RecordingsFolderPage extends StatefulWidget {
  const RecordingsFolderPage({super.key});

  @override
  State<RecordingsFolderPage> createState() => _RecordingsFolderPageState();
}

class _RecordingsFolderPageState extends State<RecordingsFolderPage> {
  List<Map<String, String>> _files = const [];
  bool _loading = true;

  /// Task 117 П.4: полный абсолютный путь к папке (показываем на экране).
  String _folderPath = '';

  /// Task 118 П.2: путь как его видит человек — без /storage/emulated/0
  /// (это та же внутренняя память, в проводнике она называется «Документы»).
  String get _displayPath {
    if (Platform.isAndroid) {
      return AudioService.publicRecordingsRelativePath;
    }
    return 'DictaPro/Записи';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _resolveFolderPath();
    final files = await AudioService.listPublicFolder();
    files.sort((a, b) =>
        (int.tryParse(b['dateMs'] ?? '0') ?? 0)
            .compareTo(int.tryParse(a['dateMs'] ?? '0') ?? 0));
    // Task 117 П.5: файл переименовали снаружи — подтягиваем новое имя
    // в базу, чтобы на главной не висело старое.
    await _syncExternalRenames(files);
    if (!mounted) return;
    setState(() {
      _files = files;
      _loading = false;
    });
  }

  Future<void> _resolveFolderPath() async {
    try {
      if (Platform.isAndroid) {
        _folderPath = AudioService.publicRecordingsDisplayPath;
      } else {
        final dir = await AudioService.recordingsDir();
        _folderPath = dir.path;
      }
    } catch (_) {}
  }

  /// Task 117 П.4 / 118 П.2: тап по пути — копировать в буфер
  /// дружелюбный вид (тот, что видит пользователь в проводнике).
  Future<void> _copyPath() async {
    final toCopy = _displayPath;
    if (toCopy.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: toCopy));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppStrings.t('folder_path_copied', context)),
      duration: const Duration(seconds: 2),
    ));
  }

  /// Task 117 П.4: «Открыть в проводнике» — Android: системный Files
  /// через DocumentsContract; iOS: своя подсказка (системные «Файлы»
  /// открывали не ту папку).
  Future<void> _openInExplorer() async {
    if (_folderPath.isEmpty) return;
    if (!Platform.isAndroid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppStrings.t('folder_ios_hint', context)),
        duration: const Duration(seconds: 4),
      ));
      return;
    }
    final ok = await AudioService.openFolderInSystemExplorer(_folderPath);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppStrings.t('folder_open_failed', context)),
      ));
    }
  }

  /// Task 117 П.5: если файл в папке переименовали снаружи — обновляем
  /// title/filePath записи в базе (иначе на главной кажется, что это
  /// два разных файла).
  Future<void> _syncExternalRenames(List<Map<String, String>> files) async {
    try {
      final box = await AudioService.openRecordingsBox();
      if (Platform.isAndroid) {
        // Точное сопоставление по contentUri.
        final byUri = <String, Map<String, String>>{};
        for (final f in files) {
          final uri = f['uri'] ?? '';
          if (uri.isNotEmpty) byUri[uri] = f;
        }
        for (final key in box.keys) {
          final raw = box.get(key);
          if (raw == null) continue;
          try {
            final rec = Recording.fromMap(Map<String, dynamic>.from(raw));
            final uri = rec.contentUri ?? '';
            if (uri.isEmpty) continue;
            final f = byUri[uri];
            if (f == null) continue;
            final newName = f['name'] ?? '';
            final oldName = rec.filePath.split(RegExp(r'[\\/]')).last;
            if (newName.isNotEmpty && newName != oldName) {
              rec.filePath = f['path']?.isNotEmpty == true
                  ? f['path']!
                  : rec.filePath;
              rec.title = newName.contains('.')
                  ? newName.substring(0, newName.lastIndexOf('.'))
                  : newName;
              await box.put(key, rec.toMap());
            }
          } catch (_) {}
        }
        return;
      }
      // iOS: сопоставление ненадёжно — минимум: файл с сохранённым именем
      // исчез — ищем по размеру среди файлов папки и обновляем путь/имя.
      final byName = <String, Map<String, String>>{};
      for (final f in files) {
        final n = f['name'] ?? '';
        if (n.isNotEmpty) byName[n] = f;
      }
      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw == null) continue;
        try {
          final rec = Recording.fromMap(Map<String, dynamic>.from(raw));
          final oldName = rec.filePath.split(RegExp(r'[\\/]')).last;
          if (oldName.isEmpty || byName.containsKey(oldName)) continue;
          Map<String, String>? match;
          for (final f in files) {
            if ((int.tryParse(f['size'] ?? '0') ?? -1) == rec.fileSize) {
              match = f;
              break;
            }
          }
          if (match == null) continue;
          final newName = match['name'] ?? '';
          rec.filePath = match['path']?.isNotEmpty == true
              ? match['path']!
              : rec.filePath;
          rec.title = newName.contains('.')
              ? newName.substring(0, newName.lastIndexOf('.'))
              : newName;
          await box.put(key, rec.toMap());
        } catch (_) {}
      }
    } catch (_) {}
  }

  String _size(int bytes) {
    if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} МБ';
    if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).toStringAsFixed(0)} КБ';
    return '$bytes Б';
  }

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// Славан: тап по файлу — файл попадает в список на главной (если его
  /// там нет) и происходит переход на главную.
  /// Task 117 П.3: главная прокрутится к записи и подсветит её рамкой.
  Future<void> _openInApp(Map<String, String> f) async {
    final name = f['name'] ?? '';
    final box = await AudioService.openRecordingsBox();
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      try {
        final rec = Recording.fromMap(Map<String, dynamic>.from(raw));
        final recName = rec.filePath.split(RegExp(r'[/]')).last;
        if (recName == name) {
          MainShell.focusRecordingId.value = rec.id;
          _goHome();
          return;
        }
      } catch (_) {}
    }
    // Нет в базе — импортируем.
    final st = f;
    final rec = Recording(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      filePath: st['path'] ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          int.tryParse(st['dateMs'] ?? '0') ?? 0),
      durationMs: 0,
      fileSize: int.tryParse(st['size'] ?? '0') ?? 0,
      title: name,
    );
    if ((st['uri'] ?? '').isNotEmpty) rec.contentUri = st['uri'];
    await AudioService().updateRecording(rec);
    MainShell.focusRecordingId.value = rec.id;
    _goHome();
  }

  void _goHome() {
    if (!mounted) return;
    MainShell.requestedTab.value = 0;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _share(Map<String, String> f) async {
    // Android: свои файлы в публичной папке шарятся по пути;
    // если путь недоступен цели — материализуем копию.
    var path = f['path'] ?? '';
    if (Platform.isAndroid && (f['uri'] ?? '').isNotEmpty) {
      try {
        final test = File(path);
        if (!await test.exists()) {
          final tmp = await AudioService.materializeUri(
              f['uri'] ?? '', f['name'] ?? 'audio.wav');
          if (tmp != null) path = tmp;
        }
      } catch (_) {}
    }
    await Share.shareXFiles([XFile(path)]);
  }

  @override
  Widget build(BuildContext context) {
    final tk = DictaTokens.of(context);
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Row(children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Expanded(
                child: Text(AppStrings.t('folder_recordings_title', context),
                    style: Theme.of(context).textTheme.headlineMedium),
              ),
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ]),
            const SizedBox(height: 6),
            // Task 117 П.4: путь к папке (тап — копировать).
            // Task 118 П.2: показываем дружелюбный вид без /storage/emulated/0
            // и подсказку, где искать папку в проводнике.
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _copyPath,
                    child: Text(_displayPath,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: tk.ink3)),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: AppStrings.t('folder_open_explorer', context),
                  icon: Icon(Icons.folder_open_rounded,
                      size: 20, color: tk.ink2),
                  onPressed: _openInExplorer,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(AppStrings.t('folder_path_hint', context),
                style: TextStyle(fontSize: 11, color: tk.ink3)),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_files.isEmpty)
              DictaCard(
                child: Text(AppStrings.t('folder_empty', context),
                    style: TextStyle(fontSize: 12.5, color: tk.ink2)),
              )
            else
              for (final f in _files)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DictaCard(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _openInApp(f),
                      child: Row(
                        children: [
                          Icon(Icons.audio_file_rounded, size: 20, color: tk.mint),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(f['name'] ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 12.5, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                  '${_size(int.tryParse(f['size'] ?? '0') ?? 0)} · ${_date(DateTime.fromMillisecondsSinceEpoch(int.tryParse(f['dateMs'] ?? '0') ?? 0))}',
                                  style: TextStyle(fontSize: 11, color: tk.ink3),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Поделиться',
                            icon: Icon(Icons.ios_share_rounded, size: 20, color: tk.ink2),
                            onPressed: () => _share(f),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
