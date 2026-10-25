// Task 116 (Славан): экран «Папка записей» для iOS — показывает файлы
// папки Documents/DictaPro/Записи с размером, датой и отправкой.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'app_strings.dart';
import 'audio_service.dart';
import 'main_shell.dart';
import 'theme/app_theme.dart';
import 'widgets/dicta_ui.dart';

class RecordingsFolderPage extends StatefulWidget {
  const RecordingsFolderPage({super.key});

  @override
  State<RecordingsFolderPage> createState() => _RecordingsFolderPageState();
}

class _RecordingsFolderPageState extends State<RecordingsFolderPage> {
  List<File> _files = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final out = <File>[];
    try {
      final dir = await AudioService.recordingsDir();
      if (await dir.exists()) {
        await for (final e in dir.list()) {
          if (e is File) out.add(e);
        }
        out.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _files = out;
      _loading = false;
    });
  }

  String _size(int bytes) {
    if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} МБ';
    if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).toStringAsFixed(0)} КБ';
    return '$bytes Б';
  }

  /// Славан: тап по файлу — открыть как запись (плеер).
  /// Если файла ещё нет в базе — добавляем (это и есть импорт) и открываем.
  Future<void> _openInApp(File f) async {
    final box = await AudioService.openRecordingsBox();
    Recording? found;
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      try {
        final rec = Recording.fromMap(Map<String, dynamic>.from(raw));
        if (rec.filePath == f.path) {
          found = rec;
          break;
        }
      } catch (_) {}
    }
    if (found == null) {
      // Славан: файла нет в списке — он появляется в списке на главной.
      final st = f.statSync();
      found = Recording(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        filePath: f.path,
        createdAt: st.modified,
        durationMs: 0,
        fileSize: st.size,
        title: f.uri.pathSegments.last,
      );
      await AudioService().updateRecording(found);
      await _load();
    }
    // Славан: после тапа — главная со списком (там можно всё), не плеер.
    if (!mounted) return;
    MainShell.requestedTab.value = 0;
    Navigator.pop(context);
  }

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final tk = DictaTokens.of(context);
    return Scaffold(
      bottomNavigationBar: DictaBottomNav(
        index: 3,
        onTap: (i) {
          Navigator.of(context).popUntil((r) => r.isFirst);
          MainShell.requestedTab.value = i;
        },
      ),
      backgroundColor: Colors.transparent,
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
            ]),
            const SizedBox(height: 6),
            Text('Documents/DictaPro/Записи',
                style: TextStyle(fontSize: 12, color: tk.ink3)),
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
                    // Task 116 (Славан): тап по файлу — открыть в приложении
                    // (плеер: прослушать, расшифровать, фрагменты).
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
                                Text(f.uri.pathSegments.last,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 12.5, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                  '${_size(f.statSync().size)} · ${_date(f.statSync().modified)}',
                                  style: TextStyle(fontSize: 11, color: tk.ink3),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Поделиться',
                            icon: Icon(Icons.ios_share_rounded, size: 20, color: tk.ink2),
                            onPressed: () => Share.shareXFiles([XFile(f.path)]),
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
