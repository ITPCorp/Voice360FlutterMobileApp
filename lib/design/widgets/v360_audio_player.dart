import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';

import '../tokens.dart';

/// Audio player used for call recordings (chat timeline + call detail modal).
///
/// Two visual modes:
///  - [V360AudioPlayer.compact] — pill-shaped row, fits inside a chat bubble
///    or a list row. Single line, no big borders.
///  - [V360AudioPlayer] (full) — taller card with bigger play button, time
///    labels, drag-to-seek, speed control, and a download button.
///
/// Both modes accept an [onPositionChanged] callback so a parent (e.g. the
/// transcript modal) can highlight the active row, and a [seekControl] that
/// exposes a seek-to-millis function back to the parent.
class V360AudioPlayer extends StatefulWidget {
  /// URL that returns the raw audio bytes (mp3/wav). For call recordings:
  /// `${BASE_URL_ITP_VOICE}/{api_id}/my-extension/cdr/{pk}/download-recording/raw?token=...`.
  final String url;

  /// Best-known total duration in seconds. Used as a placeholder before the
  /// stream loads. May be `null`.
  final int? durationSeconds;

  /// Downloadable filename (saved as on download tap).
  final String filename;

  /// If true, draws the small inline pill; otherwise the full card.
  final bool compact;

  /// Render colours tuned for an outbound (right-side) bubble background.
  /// Has no effect in non-compact mode.
  final bool onOwnBubble;

  /// Called every ~250ms with the current playback position in seconds.
  final void Function(double seconds)? onPositionChanged;

  /// Two-way handle: parent can read `.seek(seconds)` to scrub the player
  /// (e.g. clicking a transcript turn). Optional.
  final V360AudioController? controller;

  const V360AudioPlayer({
    super.key,
    required this.url,
    required this.filename,
    this.durationSeconds,
    this.compact = false,
    this.onOwnBubble = false,
    this.onPositionChanged,
    this.controller,
  });

  const V360AudioPlayer.compact({
    Key? key,
    required String url,
    required String filename,
    int? durationSeconds,
    bool onOwnBubble = false,
    void Function(double)? onPositionChanged,
    V360AudioController? controller,
  }) : this(
          key: key,
          url: url,
          filename: filename,
          durationSeconds: durationSeconds,
          compact: true,
          onOwnBubble: onOwnBubble,
          onPositionChanged: onPositionChanged,
          controller: controller,
        );

  @override
  State<V360AudioPlayer> createState() => _V360AudioPlayerState();
}

/// External handle attached to the player. Parents (e.g. the transcript
/// modal) call `seek()` to scrub the audio when a user taps a transcript row.
class V360AudioController {
  _V360AudioPlayerState? _state;

  void _attach(_V360AudioPlayerState state) => _state = state;
  void _detach(_V360AudioPlayerState state) {
    if (identical(_state, state)) _state = null;
  }

  /// Seek to a position (seconds) and start playing.
  Future<void> seek(double seconds) async {
    await _state?._seekToAndPlay(seconds);
  }

  /// Pause playback.
  Future<void> pause() async {
    await _state?._pause();
  }
}

class _V360AudioPlayerState extends State<V360AudioPlayer> {
  late final AudioPlayer _player;
  Duration _position = Duration.zero;
  Duration? _duration;
  bool _ready = false;
  bool _loading = false;
  bool _error = false;
  double _rate = 1.0;
  bool _seeking = false;

  static const List<double> _kRateOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    _player = AudioPlayer();
    _wireStreams();
  }

  void _wireStreams() {
    _player.positionStream.listen((p) {
      if (!mounted || _seeking) return;
      setState(() => _position = p);
      widget.onPositionChanged?.call(p.inMilliseconds / 1000.0);
    });
    _player.durationStream.listen((d) {
      if (!mounted || d == null) return;
      setState(() => _duration = d);
    });
    _player.playerStateStream.listen((s) {
      if (!mounted) return;
      if (s.processingState == ProcessingState.completed) {
        // Reset to start so the play button reappears.
        _player.seek(Duration.zero);
        _player.pause();
      }
      setState(() {});
    });
  }

  /// Lazily load the audio source on first play tap. We don't fetch on widget
  /// build because chat rows often render dozens of these — we'd hit the
  /// network for recordings the user might never play.
  Future<void> _ensureLoaded() async {
    if (_ready || _loading || _error) return;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      await _player.setUrl(widget.url);
      if (!mounted) return;
      setState(() {
        _ready = true;
        _loading = false;
        if (_duration == null && widget.durationSeconds != null) {
          _duration = Duration(seconds: widget.durationSeconds!);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  Future<void> _toggle() async {
    HapticFeedback.selectionClick();
    if (_error) {
      // Retry once.
      setState(() => _error = false);
    }
    await _ensureLoaded();
    if (!_ready) return;
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> _seekToAndPlay(double seconds) async {
    await _ensureLoaded();
    if (!_ready) return;
    final pos = Duration(milliseconds: (seconds * 1000).round());
    await _player.seek(pos);
    if (!_player.playing) await _player.play();
  }

  Future<void> _pause() async {
    if (_player.playing) await _player.pause();
  }

  Future<void> _setRate(double rate) async {
    setState(() => _rate = rate);
    await _player.setSpeed(rate);
  }

  Future<void> _download() async {
    try {
      // We don't have a write-to-disk capability without extra plugins yet;
      // opening the URL in the system browser hands off to the OS download.
      final uri = Uri.tryParse(widget.url);
      if (uri == null) return;
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  double get _progress {
    final total = _effectiveDuration;
    if (total <= 0) return 0;
    return (_position.inMilliseconds / 1000.0 / total).clamp(0.0, 1.0);
  }

  double get _effectiveDuration {
    if (_duration != null) return _duration!.inMilliseconds / 1000.0;
    if (widget.durationSeconds != null) return widget.durationSeconds!.toDouble();
    return 0;
  }

  String _formatSeconds(double s) {
    if (s.isNaN || s.isInfinite || s < 0) return '0:00';
    final m = (s ~/ 60);
    final sec = (s % 60).toInt().toString().padLeft(2, '0');
    return '$m:$sec';
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.compact ? _buildCompact(context) : _buildFull(context);
  }

  // --------------------------------------------------------------------- //
  // Compact pill — embedded inside chat bubbles or list rows
  // --------------------------------------------------------------------- //
  Widget _buildCompact(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onOwn = widget.onOwnBubble;
    final accent = onOwn ? cs.onPrimary : cs.primary;
    final muted = onOwn
        ? cs.onPrimary.withOpacity(0.7)
        : cs.onSurfaceVariant;
    final track = onOwn
        ? cs.onPrimary.withOpacity(0.25)
        : cs.outlineVariant;
    final bg = onOwn
        ? cs.onPrimary.withOpacity(0.12)
        : cs.surfaceContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(V360Radius.xl),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _playButton(size: 28, color: accent, onBg: onOwn),
          const SizedBox(width: V360Spacing.s2),
          Text(
            _formatSeconds(_position.inMilliseconds / 1000.0),
            style: TextStyle(
                color: accent, fontWeight: FontWeight.w600, fontSize: 11),
          ),
          const SizedBox(width: V360Spacing.s2),
          Flexible(
            child: SizedBox(
              width: 120,
              child: _Progress(
                progress: _progress,
                trackColor: track,
                fillColor: accent,
                onSeek: _ready ? _onSeekFraction : null,
              ),
            ),
          ),
          const SizedBox(width: V360Spacing.s2),
          Text(
            _formatSeconds(_effectiveDuration),
            style: TextStyle(color: muted, fontSize: 10),
          ),
          const SizedBox(width: V360Spacing.s1),
          _SpeedButton(
            rate: _rate,
            color: muted,
            onSelect: _setRate,
            options: _kRateOptions,
            compact: true,
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------- //
  // Full mode — used in transcript modal / call detail screens
  // --------------------------------------------------------------------- //
  Widget _buildFull(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(V360Spacing.s4),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(V360Radius.xl),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: V360Shadows.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _playButton(size: 48, color: cs.primary),
              const SizedBox(width: V360Spacing.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _formatSeconds(_position.inMilliseconds / 1000.0),
                          style: tt.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _formatSeconds(_effectiveDuration),
                          style: tt.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _Progress(
                      progress: _progress,
                      trackColor: cs.outlineVariant,
                      fillColor: cs.primary,
                      onSeek: _ready ? _onSeekFraction : null,
                      thick: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: V360Spacing.s3),
          Row(
            children: [
              _SpeedButton(
                rate: _rate,
                color: cs.onSurface,
                onSelect: _setRate,
                options: _kRateOptions,
              ),
              const Spacer(),
              if (_error)
                Text(
                  'Could not load audio',
                  style: tt.labelSmall?.copyWith(color: cs.error),
                ),
              const SizedBox(width: V360Spacing.s2),
              IconButton(
                tooltip: 'Download',
                onPressed: _download,
                icon: Icon(Icons.download_rounded, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _playButton({
    required double size,
    required Color color,
    bool onBg = false,
  }) {
    final inner = size <= 32 ? 14.0 : 22.0;
    IconData icon;
    Widget? overlay;
    if (_loading) {
      overlay = SizedBox(
        width: inner,
        height: inner,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(onBg ? color : Colors.white),
        ),
      );
      icon = Icons.play_arrow_rounded;
    } else if (_error) {
      icon = Icons.refresh_rounded;
    } else if (_player.playing) {
      icon = Icons.pause_rounded;
    } else {
      icon = Icons.play_arrow_rounded;
    }
    return InkResponse(
      onTap: _toggle,
      radius: size,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: onBg ? Colors.white.withOpacity(0.25) : color,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: overlay ??
            Icon(icon,
                color: onBg ? color : Colors.white, size: inner),
      ),
    );
  }

  Future<void> _onSeekFraction(double fraction) async {
    final total = _effectiveDuration;
    if (total <= 0) return;
    setState(() {
      _seeking = true;
      _position = Duration(milliseconds: (fraction * total * 1000).round());
    });
    try {
      await _player.seek(_position);
    } finally {
      if (mounted) setState(() => _seeking = false);
    }
  }
}

// --------------------------------------------------------------------------
// Progress bar — taps & drags map to a fraction in [0, 1].
// --------------------------------------------------------------------------
class _Progress extends StatelessWidget {
  final double progress;
  final Color trackColor;
  final Color fillColor;
  final Future<void> Function(double fraction)? onSeek;
  final bool thick;

  const _Progress({
    required this.progress,
    required this.trackColor,
    required this.fillColor,
    this.onSeek,
    this.thick = false,
  });

  @override
  Widget build(BuildContext context) {
    final h = thick ? 5.0 : 3.0;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: onSeek == null
          ? null
          : (details) {
              final box = context.findRenderObject() as RenderBox?;
              if (box == null) return;
              final dx = (details.localPosition.dx / box.size.width)
                  .clamp(0.0, 1.0);
              onSeek!(dx);
            },
      onHorizontalDragUpdate: onSeek == null
          ? null
          : (details) {
              final box = context.findRenderObject() as RenderBox?;
              if (box == null) return;
              final dx = (details.localPosition.dx / box.size.width)
                  .clamp(0.0, 1.0);
              onSeek!(dx);
            },
      child: SizedBox(
        height: h + 8,
        child: Align(
          alignment: Alignment.center,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(h),
            child: Container(
              height: h,
              color: trackColor,
              child: FractionallySizedBox(
                widthFactor: progress,
                alignment: Alignment.centerLeft,
                child: Container(color: fillColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------------
// Speed dropdown — shows a Cupertino-style popup with options.
// --------------------------------------------------------------------------
class _SpeedButton extends StatelessWidget {
  final double rate;
  final Color color;
  final List<double> options;
  final ValueChanged<double> onSelect;
  final bool compact;

  const _SpeedButton({
    required this.rate,
    required this.color,
    required this.options,
    required this.onSelect,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      tooltip: 'Playback speed',
      initialValue: rate,
      onSelected: onSelect,
      itemBuilder: (_) => [
        for (final r in options)
          PopupMenuItem<double>(
            value: r,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (r == rate) ...[
                  const Icon(Icons.check_rounded, size: 14),
                  const SizedBox(width: 6),
                ] else
                  const SizedBox(width: 20),
                Text('${_label(r)}×'),
              ],
            ),
          ),
      ],
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 10,
          vertical: compact ? 2 : 4,
        ),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(V360Radius.base),
        ),
        child: Text(
          '${_label(rate)}×',
          style: TextStyle(
            color: color,
            fontSize: compact ? 10 : 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  String _label(double r) {
    if (r == r.roundToDouble()) return r.toStringAsFixed(0);
    return r.toString();
  }
}
