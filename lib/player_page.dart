import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_strings.dart';
import 'package:share_plus/share_plus.dart';
import 'services/share_helper.dart';
import 'services/audio_fragment_service.dart';
import 'audio_service.dart';
import 'theme/app_theme.dart';

class PlayerPage extends StatefulWidget {
  final Recording recording;

  const PlayerPage({super.key, required this.recording});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final _player = AudioPlayer();
  final _scrollController = ScrollController();
  bool _isPlaying = false;
  bool _audioMissing = false;
  bool _userScrolling = false;
  double _speed = 1.0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  late List<DialogueSegment> _segments;

  // 20.10: выделение строк прямо в плеере → вырезать фрагмент.
  bool _selectMode = false;
  final Set<int> _selected = <int>{};
  bool _exportingFragment = false;

  // Task 107: режим «синхронно» — автоскролл к звучащей фразе (по умолчанию ВЫКЛ)
  bool _followMode = false;
  double _scrollOffset = 0.0;
  static const String _followPrefKey = 'player_follow_mode';

  /// Высоты полосок волны (как в макете — фиксированный узор).
  static const List<double> _waveHeights = [
    10, 22, 34, 48, 30, 16, 24, 40, 52, 34, 20, 12,
    26, 42, 30, 18, 10, 28, 44, 32, 16, 24, 38, 20, 12,
  ];

  @override
  void initState() {
    super.initState();
    _segments = widget.recording.segments?.map((s) {
          return DialogueSegment.fromMap(Map<String, dynamic>.from(s));
        }).toList() ??
        [];
    if (_segments.isEmpty && widget.recording.transcription != null) {
      _segments = [
        DialogueSegment(
            speaker: 'Фраза 1', text: widget.recording.transcription!)
      ];
    }
    // Task 107: следим за скроллом — для стрелки-индикатора в свободном режиме
    _scrollController.addListener(_onScroll);
    _loadFollowMode();
    _initPlayer();
  }

  Future<void> _loadFollowMode() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getBool(_followPrefKey) ?? false;
    if (mounted) setState(() => _followMode = v);
  }

  Future<void> _setFollowMode(bool v) async {
    setState(() => _followMode = v);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_followPrefKey, v);
    if (v) {
      // Включили синхронизацию — сразу подтягиваем ленту к звучащей фразе
      _userScrolling = false;
      _scrollToActive();
    }
  }

  void _onScroll() {
    if (!mounted || !_scrollController.hasClients) return;
    final o = _scrollController.offset;
    if ((o - _scrollOffset).abs() < 0.5) return;
    setState(() => _scrollOffset = o);
  }

  /// Task 107: направление стрелки к звучащей фразе (-1 вверх, 1 вниз, 0 — видна).
  int _arrowDirFor(int active) {
    if (_followMode || active < 0 || !_scrollController.hasClients) return 0;
    const itemHeight = 80.0;
    final top = active * itemHeight;
    final offset = _scrollController.offset;
    final viewport = _scrollController.position.viewportDimension;
    if (top < offset) return -1;
    if (top + itemHeight > offset + viewport) return 1;
    return 0;
  }

  Future<void> _initPlayer() async {
    try {
      final resolved =
          await AudioService.resolveFilePath(widget.recording.filePath);
      await _player.setFilePath(resolved);
      _duration = _player.duration ?? Duration.zero;
    } catch (_) {
      _audioMissing = true;
    }
    if (mounted) setState(() {});

    _player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });

    _player.playerStateStream.listen((state) {
      if (mounted) setState(() => _isPlaying = state.playing);
    });
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _defaultName() {
    final d = widget.recording.createdAt;
    String two(int v) => v.toString().padLeft(2, '0');
    return AppStrings.tf('recording_of', context,
        {'d': '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}'});
  }

  Future<void> _togglePlay() async {
    if (_audioMissing) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.t('audio_lost_snack', context)),
        ),
      );
      return;
    }
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  void _setSpeed(double speed) {
    setState(() => _speed = speed);
    _player.setSpeed(speed);
  }

  /// Task 106: seek + прокрутка списка к активной фразе (только в режиме «синхронно»).
  Future<void> _seek(double value) async {
    final pos =
        Duration(milliseconds: (value * _duration.inMilliseconds).round());
    await _player.seek(pos);
    if (_followMode) _scrollToActive();
  }

  Future<void> _skip(int seconds) async {
    var target = _position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (_duration > Duration.zero && target > _duration) target = _duration;
    await _player.seek(target);
    if (_followMode) _scrollToActive();
  }

  /// Прокрутка списка к активной фразе.
  void _scrollToActive() {
    if (_segments.isEmpty) return;
    final starts = _starts();
    final ends = _ends();
    final active = _activeSegment(starts, ends);
    if (active < 0 || !_scrollController.hasClients) return;

    // Примерная высота одной фразы (~80 px на основе текущего дизайна)
    const itemHeight = 80.0;
    final target = active * itemHeight;
    final viewport = _scrollController.position.viewportDimension;
    // Центрируем активную фразу в видимой зоне
    final offset = (target - viewport / 2 + itemHeight / 2)
        .clamp(0.0, _scrollController.position.maxScrollExtent);

    _scrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _player.dispose();
    super.dispose();
  }

  bool get _hasRealTimes => _segments.any((s) => s.endTime > s.startTime);

  double get _totalSeconds {
    final ms = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds
        : widget.recording.durationMs;
    return ms / 1000.0;
  }

  List<double> _starts() {
    if (_hasRealTimes) {
      return [for (final s in _segments) s.startTime];
    }
    final total = _segments.fold<int>(
        0, (a, s) => a + (s.text.isEmpty ? 1 : s.text.length));
    final dur = _totalSeconds;
    final out = <double>[];
    var acc = 0;
    for (final s in _segments) {
      out.add(total > 0 ? dur * acc / total : 0.0);
      acc += s.text.isEmpty ? 1 : s.text.length;
    }
    return out;
  }

  List<double> _ends() {
    final starts = _starts();
    final out = <double>[];
    for (var i = 0; i < starts.length; i++) {
      final next = i + 1 < starts.length ? starts[i + 1] : _totalSeconds;
      if (_hasRealTimes && _segments[i].endTime > _segments[i].startTime) {
        out.add(_segments[i].endTime);
      } else {
        out.add(next);
      }
    }
    return out;
  }

  int _activeSegment(List<double> starts, List<double> ends) {
    final pos = _position.inMilliseconds / 1000.0;
    var last = -1;
    for (var i = 0; i < starts.length; i++) {
      if (pos >= starts[i]) last = i;
      if (pos >= starts[i] && pos < ends[i]) return i;
    }
    return last;
  }

  @override
  Widget build(BuildContext context) {
    final tk = DictaTokens.of(context);
    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;
    final starts = _starts();
    final ends = _ends();
    final active = _activeSegment(starts, ends);
    final speakerNo = <String, int>{};
    for (final s in _segments) {
      speakerNo.putIfAbsent(s.speaker, () => speakerNo.length + 1);
    }
    final totalDur = _duration > Duration.zero
        ? _duration
        : Duration(milliseconds: widget.recording.durationMs);

    final subText = _segments.isEmpty
        ? _fmtDuration(totalDur)
        : '${_fmtDuration(totalDur)} · ${AppStrings.tf('player_segment_of', context, {
            'i': '${active < 0 ? 1 : active + 1}',
            'n': '${_segments.length}',
          })}';

    // Task 106/107: автопрокрутка при воспроизведении — только в режиме «синхронно»
    if (_followMode && _isPlaying && !_userScrolling && active >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToActive();
      });
    }

    final arrowDir = _arrowDirFor(active);

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
              Text(
                widget.recording.title ?? _defaultName(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 2),
              Text(
                subText,
                style: tk.mono(10.5, FontWeight.w500, tk.mint),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(
                _selectMode ? Icons.close_rounded : Icons.content_cut_rounded,
                size: 18,
                color: _selectMode ? tk.mint : tk.ink2,
              ),
              tooltip: AppStrings.t('fragment_mode', context),
              onPressed: () => setState(() {
                _selectMode = !_selectMode;
                _selected.clear();
              }),
            ),
            PopupMenuButton<double>(
              initialValue: _speed,
              onSelected: _setSpeed,
              tooltip: AppStrings.t('player_speed', context),
              icon: Icon(Icons.speed_rounded, size: 18, color: tk.ink2),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 0.5, child: Text('0.5x')),
                PopupMenuItem(value: 1.0, child: Text('1.0x')),
                PopupMenuItem(value: 1.25, child: Text('1.25x')),
                PopupMenuItem(value: 1.5, child: Text('1.5x')),
                PopupMenuItem(value: 2.0, child: Text('2.0x')),
              ],
            ),
            const SizedBox(width: 8),
          ],
        ),
        // Task 106: верхний блок зафиксирован, список фраз скроллится отдельно
        body: Column(
          children: [
            // ─── Фиксированный блок управления ───
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Column(
                children: [
                  if (_audioMissing) ...[
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: tk.red.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: tk.red.withValues(alpha: 0.30)),
                      ),
                      child: Text(
                        AppStrings.t('audio_lost_banner', context),
                        style: TextStyle(
                            fontSize: 11.5, color: tk.ink2, height: 1.5),
                      ),
                    ),
                  ],
                  _progressBar(tk, progress),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(_fmtDuration(_position),
                          style: tk.mono(11, FontWeight.w600, tk.ink3)),
                      const Spacer(),
                      Text(_fmtDuration(totalDur),
                          style: tk.mono(11, FontWeight.w600, tk.ink3)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _miniButton(tk, '−15', () => _skip(-15)),
                      const SizedBox(width: 18),
                      _playButton(),
                      const SizedBox(width: 18),
                      _miniButton(tk, '+30', () => _skip(30)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final v in const [0.5, 1.0, 1.5, 2.0]) ...[
                        if (v != 0.5) const SizedBox(width: 8),
                        _speedChip(tk, v),
                      ],
                    ],
                  ),
                  if (_segments.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            AppStrings.t('player_seek_section', context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: tk.ink),
                          ),
                        ),
                        // Task 107: галка «Аудио+текст синхронно»
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _setFollowMode(!_followMode),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: Checkbox(
                                    value: _followMode,
                                    onChanged: (v) =>
                                        _setFollowMode(v ?? false),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                    side: BorderSide(
                                        color: tk.line2, width: 1.4),
                                    activeColor: tk.mint,
                                    checkColor: AppColors.mintInk,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  AppStrings.t('player_follow', context),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: tk.ink2),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        AppStrings.t('player_seek_hint', context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: tk.mint),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // ─── Скроллируемый список фраз ───
            if (_segments.isNotEmpty)
              Expanded(
                child: Stack(
                  children: [
                    NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        // Отслеживаем ручной скролл — пауза автопрокрутки
                        if (notification is ScrollStartNotification &&
                            notification.dragDetails != null) {
                          _userScrolling = true;
                        }
                        if (notification is ScrollEndNotification) {
                          // Возобновляем автоскролл после паузы
                          Future.delayed(const Duration(seconds: 2), () {
                            if (mounted) _userScrolling = false;
                          });
                        }
                        return false;
                      },
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                        itemCount: _segments.length,
                        itemBuilder: (context, i) =>
                            _segmentRow(tk, i, starts, speakerNo, active),
                      ),
                    ),
                    // Task 107: стрелка к звучащей фразе (только без «синхронно»)
                    if (arrowDir != 0)
                      Positioned(
                        right: 8,
                        top: 0,
                        bottom: 24,
                        child: IgnorePointer(
                          child: Center(
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: tk.mint.withValues(alpha: 0.14),
                                border: Border.all(
                                    color: tk.mint.withValues(alpha: 0.35)),
                              ),
                              child: Icon(
                                arrowDir < 0
                                    ? Icons.arrow_upward_rounded
                                    : Icons.arrow_downward_rounded,
                                size: 18,
                                color: tk.mint.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (_selectMode) _selectionBar(tk),
          ],
        ),
      ),
    );
  }

  // 20.10: панель «Выбрано строк» + «Вырезать фрагмент» в плеере.
  Widget _selectionBar(DictaTokens tk) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: tk.surface2,
        border: Border(top: BorderSide(color: tk.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              AppStrings.tf('fragment_selected', context,
                  {'n': '${_selected.length}'}),
              style: TextStyle(fontSize: 12, color: tk.ink2),
            ),
          ),
          ElevatedButton.icon(
            onPressed: (_selected.isEmpty || _exportingFragment)
                ? null
                : _exportFragment,
            icon: _exportingFragment
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.content_cut_rounded, size: 16),
            label: Text(AppStrings.t('fragment_export', context)),
          ),
        ],
      ),
    );
  }

  Future<void> _exportFragment() async {
    if (_selected.isEmpty || _exportingFragment) return;
    final idx = _selected.toList()..sort();
    final first = idx.first;
    final last = idx.last;
    final start = _segments[first].startTime;
    var end = _segments[last].endTime;
    if (end <= start) end = start + AudioFragmentService.fallbackSec;

    setState(() => _exportingFragment = true);
    final path = await AudioFragmentService.exportFragment(
      storedPath: widget.recording.filePath,
      startSec: start,
      endSec: end,
    );
    if (!mounted) return;
    setState(() => _exportingFragment = false);

    if (path == null) {
      final reason = AudioFragmentService.lastError ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(reason.isEmpty
              ? AppStrings.t('fragment_failed', context)
              : '${AppStrings.t('fragment_failed', context)}: $reason'),
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppStrings.t('fragment_saved', context)),
        action: SnackBarAction(
          label: AppStrings.t('share_title', context),
          onPressed: () async => await shareFileWithReturn(path),
        ),
      ),
    );
  }

  Widget _progressBar(DictaTokens tk, double progress) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      void seekTo(double dx) {
        if (width <= 0) return;
        _seek((dx / width).clamp(0.0, 1.0));
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => seekTo(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => seekTo(d.localPosition.dx),
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var i = 0; i < _waveHeights.length; i++) ...[
                if (i > 0) const SizedBox(width: 3),
                Expanded(
                  child: Container(
                    height: _waveHeights[i],
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      color: (i + 1) / _waveHeights.length <= progress
                          ? null
                          : tk.line,
                      gradient: (i + 1) / _waveHeights.length <= progress
                          ? LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [tk.mint, AppColors.mint2],
                            )
                          : null,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    });
  }

  Widget _playButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _togglePlay,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFF7E7E), AppColors.red],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x47FF6B6B),
                blurRadius: 26,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Icon(
            _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 30,
            color: AppColors.redInk,
          ),
        ),
      ),
    );
  }

  Widget _miniButton(DictaTokens tk, String label, VoidCallback onTap) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: tk.line2),
        ),
        child: Text(label, style: tk.mono(11, FontWeight.w700, tk.ink)),
      ),
    );
  }

  Widget _speedChip(DictaTokens tk, double value) {
    final isActive = _speed == value;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => _setSpeed(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? tk.mint : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: isActive ? tk.mint : tk.line),
        ),
        child: Text(
          '${value.toStringAsFixed(1)}×',
          style: tk.mono(
            12,
            isActive ? FontWeight.w700 : FontWeight.w500,
            isActive ? AppColors.mintInk : tk.ink2,
          ),
        ),
      ),
    );
  }

  Widget _segmentRow(DictaTokens tk, int i, List<double> starts,
      Map<String, int> speakerNo, int active) {
    final segment = _segments[i];
    final isActive = i == active;
    final start = starts[i];
    final timecode =
        _fmtDuration(Duration(milliseconds: (start * 1000).round()));

    final selected = _selected.contains(i);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        if (_selectMode) {
          setState(() {
            if (!_selected.remove(i)) _selected.add(i);
          });
          return;
        }
        if (_audioMissing) return;
        await _player.seek(Duration(milliseconds: (start * 1000).round()));
        if (!_isPlaying) await _player.play();
      },
      // Task 106: яркая подсветка активной фразы
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 11),
        padding: const EdgeInsets.only(left: 10, right: 8, top: 6, bottom: 6),
        decoration: BoxDecoration(
          color: isActive ? tk.mint.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
              color: selected
                  ? tk.mint
                  : tk.mint.withValues(alpha: isActive ? 1.0 : 0.35),
              width: selected ? 4 : 3,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_selectMode)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Checkbox(
                  value: selected,
                  onChanged: (_) => setState(() {
                    if (!_selected.remove(i)) _selected.add(i);
                  }),
                ),
              ),
            Expanded(
              child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$timecode · ${AppStrings.tf('dialogue_speaker', context, {'n': '${i + 1}'})}',
              style: tk.mono(10.5, FontWeight.w700,
                  isActive ? tk.mint : tk.ink3),
            ),
            const SizedBox(height: 3),
            Text(
              segment.text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: isActive ? tk.ink : tk.ink2,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
            ),
          ],
        ),
      ),
    );
  }
}
