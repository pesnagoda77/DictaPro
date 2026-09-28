import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'audio_service.dart';
import 'export_service.dart';
import 'theme/app_theme.dart';

class DialogueEditor extends StatefulWidget {
  final Recording recording;

  const DialogueEditor({super.key, required this.recording});

  @override
  State<DialogueEditor> createState() => _DialogueEditorState();
}

class _DialogueEditorState extends State<DialogueEditor> {
  late List<DialogueSegment> _segments;
  final _textControllers = <TextEditingController>[];
  final _focusNodes = <FocusNode>[];
  final _lastCursorPositions = <int>[];
  int _activeIndex = 0;

  @override
  void initState() {
    super.initState();
    _segments = widget.recording.segments?.map((s) {
          return DialogueSegment.fromMap(Map<String, dynamic>.from(s));
        }).toList() ??
        [];

    if (_segments.isEmpty && widget.recording.transcription != null) {
      _segments = [
        DialogueSegment(speaker: 'A', text: widget.recording.transcription!)
      ];
    }

    _initControllers();
  }

  void _initControllers() {
    for (var c in _textControllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    _textControllers.clear();
    _focusNodes.clear();
    _lastCursorPositions.clear();

    for (var i = 0; i < _segments.length; i++) {
      final segment = _segments[i];
      final controller = TextEditingController(text: segment.text);
      final focusNode = FocusNode();
      final idx = i;

      controller.addListener(() {
        final cursorPos = controller.selection.baseOffset;
        if (cursorPos >= 0) {
          final index = _textControllers.indexOf(controller);
          if (index >= 0 && index < _lastCursorPositions.length) {
            _lastCursorPositions[index] = cursorPos;
          }
        }
      });

      focusNode.addListener(() {
        if (focusNode.hasFocus) {
          _activeIndex = idx;
        }
      });

      _textControllers.add(controller);
      _focusNodes.add(focusNode);
      _lastCursorPositions.add(segment.text.length);
    }

    if (_activeIndex >= _segments.length) {
      _activeIndex = _segments.length - 1;
    }
    if (_activeIndex < 0) {
      _activeIndex = 0;
    }
  }

  void _splitAtCursor(int index) {
    final controller = _textControllers[index];
    final cursorPos = controller.selection.baseOffset;

    if (cursorPos <= 0 || cursorPos >= controller.text.length) {
      final savedPos = _lastCursorPositions[index];
      if (savedPos <= 0 || savedPos >= controller.text.length) {
        _splitSegment(index, controller.text.length ~/ 2);
        return;
      }
      _splitSegment(index, savedPos);
      return;
    }

    _splitSegment(index, cursorPos);
  }

  void _splitSegment(int index, int cursorPosition) {
    final text = _textControllers[index].text;
    if (cursorPosition <= 0 || cursorPosition >= text.length) return;

    final before = text.substring(0, cursorPosition).trim();
    final after = text.substring(cursorPosition).trim();

    if (before.isEmpty || after.isEmpty) return;

    setState(() {
      _segments[index].text = before;
      final newSpeaker = _segments[index].speaker == 'A' ? 'B' : 'A';
      _segments.insert(
          index + 1, DialogueSegment(speaker: newSpeaker, text: after));
      _initControllers();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (index + 1 < _focusNodes.length) {
        _focusNodes[index + 1].requestFocus();
      }
    });
  }

  void _mergeWithPrevious(int index) {
    if (index <= 0) return;

    setState(() {
      _segments[index - 1].text += ' ${_segments[index].text}';
      _segments.removeAt(index);
      _initControllers();
    });
  }

  void _toggleSpeaker(int index) {
    setState(() {
      _segments[index].speaker = _segments[index].speaker == 'A' ? 'B' : 'A';
    });
  }

  void _deleteSegment(int index) {
    if (_segments.length <= 1) return;

    setState(() {
      _segments.removeAt(index);
      _initControllers();
    });
  }

  Future<void> _save() async {
    for (int i = 0; i < _segments.length; i++) {
      _segments[i].text = _textControllers[i].text;
    }

    final fullText = _segments.map((s) => _segments.map((x) => x.speaker).toSet().length > 1 ? '${s.speaker}: ${s.text}' : s.text).join('\n');
    widget.recording.transcription = fullText;
    widget.recording.segments = _segments.map((s) => s.toMap()).toList();

    await AudioService().updateRecording(widget.recording);

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  void _copyToClipboard() {
    final text = _segments.map((s) => _segments.map((x) => x.speaker).toSet().length > 1 ? '${s.speaker}: ${s.text}' : s.text).join('\n');
    ExportService.copyToClipboard(text);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Скопировано в буфер обмена')),
    );
  }

  void _shareText() {
    final text = _segments.map((s) => _segments.map((x) => x.speaker).toSet().length > 1 ? '${s.speaker}: ${s.text}' : s.text).join('\n');
    ExportService.shareText(text);
  }

  void _exportHtml() async {
    final html = ExportService.formatTranscriptHtml(widget.recording);
    final fileName = 'transcript_${widget.recording.id}';
    final path = await ExportService.saveAsTxt(html, fileName);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('HTML сохранён: $path')),
    );
  }

  @override
  void dispose() {
    for (var c in _textControllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String _plural(int n, String one, String few, String many) {
    final m10 = n % 10;
    final m100 = n % 100;
    if (m10 == 1 && m100 != 11) return one;
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
    return many;
  }

  int get _active {
    if (_segments.isEmpty) return 0;
    if (_activeIndex < 0) return 0;
    if (_activeIndex >= _segments.length) return _segments.length - 1;
    return _activeIndex;
  }

  @override
  Widget build(BuildContext context) {
    final tk = DictaTokens.of(context);
    final speakerNo = <String, int>{};
    for (final s in _segments) {
      speakerNo.putIfAbsent(s.speaker, () => speakerNo.length + 1);
    }
    final replics = _plural(_segments.length, 'реплика', 'реплики', 'реплик');
    final spk = _plural(speakerNo.length, 'говорящий', 'говорящих', 'говорящих');
    final subtitle =
        '${_segments.length} $replics · ${speakerNo.length} $spk · разметка вручную';

    return DictaBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleSpacing: 16,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Диалог', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10.5,
                  color: tk.mint,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.copy_rounded),
              iconSize: 18,
              color: tk.ink2,
              tooltip: 'Копировать текст',
              onPressed: _copyToClipboard,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: _shareText,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    border: Border.all(color: tk.line),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Поделиться',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: tk.ink2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, size: 18, color: tk.ink2),
              onSelected: (value) {
                if (value == 'html') _exportHtml();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'html',
                  child: Row(
                    children: [
                      const Icon(Icons.code, size: 20),
                      const SizedBox(width: 8),
                      Text(AppStrings.t('export_html', context)),
                    ],
                  ),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.save_rounded),
              iconSize: 18,
              color: tk.ink2,
              tooltip: 'Сохранить',
              onPressed: _save,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _tool(tk, 'Поменять говорящего', () => _toggleSpeaker(_active)),
                  _tool(tk, 'Разделить реплику', () => _splitAtCursor(_active)),
                  _tool(tk, 'Объединить', () => _mergeWithPrevious(_active)),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                itemCount: _segments.length + 1,
                itemBuilder: (context, index) {
                  if (index == _segments.length) {
                    return _footerNote(tk);
                  }
                  return _segmentBlock(tk, index, speakerNo);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tool(DictaTokens tk, String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: tk.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, color: tk.ink2)),
      ),
    );
  }

  Widget _segmentBlock(DictaTokens tk, int index, Map<String, int> speakerNo) {
    final segment = _segments[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: tk.mint.withValues(alpha: 0.35), width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'ГОВОРЯЩИЙ ${speakerNo[segment.speaker] ?? 1}',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: tk.mint,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              if (_segments.length > 1)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  iconSize: 15,
                  color: tk.ink3,
                  tooltip: 'Удалить',
                  onPressed: () => _deleteSegment(index),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
            ],
          ),
          const SizedBox(height: 3),
          TextField(
            controller: _textControllers[index],
            focusNode: _focusNodes[index],
            maxLines: null,
            cursorColor: tk.mint,
            style: TextStyle(fontSize: 12.5, height: 1.45, color: tk.ink),
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintText: AppStrings.t('enter_text_hint', context),
              hintStyle: TextStyle(color: tk.ink3, fontSize: 12.5),
            ),
          ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }

  Widget _footerNote(DictaTokens tk) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tk.line)),
      ),
      child: Text(
        'Разметка хранится только на устройстве. Экспорт может включать или не включать подписи говорящих.',
        style: TextStyle(fontSize: 10.5, height: 1.5, color: tk.ink3),
      ),
    );
  }
}
