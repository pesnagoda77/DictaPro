import 'package:flutter/material.dart';
import 'app_strings.dart';
import 'package:just_audio/just_audio.dart';
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
  bool _isPlaying = false;
  bool _audioMissing = false;
  double _speed = 1.0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  late List<DialogueSegment> _segments;

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
            speaker: 'Speaker 1', text: widget.recording.transcription!)
      ];
    }
    _initPlayer();
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
    return 'Запись ${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _togglePlay() async {
    if (_audioMissing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Аудио этой записи не найдено — файл потерян старой версией (исправлено 29.09)'),
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

  Future<void> _seek(double value) async {
    final pos =
        Duration(milliseconds: (value * _duration.inMilliseconds).round());
    await _player.seek(pos);
  }

  Future<void> _skip(int seconds) async {
    var target = _position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (_duration > Duration.zero && target > _duration) target = _duration;
    await _player.seek(target);
  }

  @override
  void dispose() {
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
            PopupMenuButton<double>(
              initialValue: _speed,
              onSelected: _setSpeed,
              tooltip: 'Скорость',
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
        body: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              sliver: SliverToBoxAdapter(
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
                          'Аудио этой записи не найдено — файл был потерян старой версией приложения (исправлено с 29.09). Новые записи сохраняются.',
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
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              AppStrings.t('player_seek_hint', context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 11.5, color: tk.mint),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              sliver: SliverList.builder(
                itemCount: _segments.length,
                itemBuilder: (context, i) =>
                    _segmentRow(tk, i, starts, speakerNo, active),
              ),
            ),
          ],
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

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        if (_audioMissing) return;
        await _player.seek(Duration(milliseconds: (start * 1000).round()));
        if (!_isPlaying) await _player.play();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 11),
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: tk.mint.withValues(alpha: isActive ? 0.9 : 0.35),
              width: 2,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$timecode · ${AppStrings.tf('dialogue_speaker', context, {'n': '${speakerNo[segment.speaker] ?? 1}'})}',
              style: tk.mono(10.5, FontWeight.w700, tk.mint),
            ),
            const SizedBox(height: 3),
            Text(
              segment.text,
              style: TextStyle(fontSize: 12.5, height: 1.5, color: tk.ink),
            ),
          ],
        ),
      ),
    );
  }
}
