import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:itp_voice/design/v360.dart';
import 'package:itp_voice/services/call_media.dart';

/// Full-screen modal that plays a call recording and lets the user follow
/// along with the parsed transcript (left column = agent, right = customer).
///
/// Open via:
/// ```dart
/// Navigator.of(context).push(MaterialPageRoute(
///   builder: (_) => TranscriptModal(
///     recordingUrl: url,
///     transcription: rawJson,
///     callerLabel: 'Jane Doe',
///     myLabel: 'You',
///     durationSeconds: 342,
///   ),
/// ));
/// ```
class TranscriptModal extends StatefulWidget {
  /// Authenticated URL pointing at the raw audio file. `null` hides the
  /// player and shows a static transcript.
  final String? recordingUrl;

  /// Raw JSON string from `call_transcription`. `null` hides the transcript.
  final String? transcription;

  /// Display name for the local participant (the user). Defaults to "You".
  final String myLabel;

  /// Display name for the remote participant. Defaults to "Caller".
  final String callerLabel;

  /// Best-known call duration in seconds. Passed to the player so it shows a
  /// total before the stream loads.
  final int? durationSeconds;

  /// What to call the recording when downloaded.
  final String filename;

  const TranscriptModal({
    super.key,
    required this.recordingUrl,
    required this.transcription,
    this.myLabel = 'You',
    this.callerLabel = 'Caller',
    this.durationSeconds,
    this.filename = 'call-recording.wav',
  });

  @override
  State<TranscriptModal> createState() => _TranscriptModalState();
}

class _TranscriptModalState extends State<TranscriptModal> {
  late final ParsedTranscript _transcript;
  final V360AudioController _player = V360AudioController();
  final ScrollController _scroll = ScrollController();
  final Map<int, GlobalKey> _turnKeys = {};
  int _activeIndex = -1;

  @override
  void initState() {
    super.initState();
    _transcript = parseTranscription(widget.transcription);
    for (int i = 0; i < _transcript.turns.length; i++) {
      _turnKeys[i] = GlobalKey();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onPosition(double seconds) {
    // Find the active turn — last turn whose start <= position.
    int active = -1;
    for (int i = 0; i < _transcript.turns.length; i++) {
      if (_transcript.turns[i].startSeconds <= seconds) {
        active = i;
      } else {
        break;
      }
    }
    if (active != _activeIndex) {
      setState(() => _activeIndex = active);
      _scrollToActive(active);
    }
  }

  void _scrollToActive(int index) {
    if (index < 0) return;
    final key = _turnKeys[index];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 220),
      alignment: 0.4,
      curve: Curves.easeOut,
    );
  }

  Future<void> _onTurnTap(TranscriptTurn turn) async {
    HapticFeedback.selectionClick();
    await _player.seek(turn.startSeconds);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasRecording =
        widget.recordingUrl != null && widget.recordingUrl!.isNotEmpty;
    final hasTranscript = _transcript.turns.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Call details'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Summary + player (sticky top section)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                V360Spacing.s4,
                V360Spacing.s3,
                V360Spacing.s4,
                V360Spacing.s2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_transcript.summary != null)
                    _SummaryCard(summary: _transcript.summary!),
                  if (_transcript.summary != null)
                    const SizedBox(height: V360Spacing.s3),
                  if (hasRecording)
                    V360AudioPlayer(
                      url: widget.recordingUrl!,
                      filename: widget.filename,
                      durationSeconds: widget.durationSeconds,
                      controller: _player,
                      onPositionChanged: _onPosition,
                    ),
                ],
              ),
            ),
            // Header labels — only when transcript exists
            if (hasTranscript) ...[
              const SizedBox(height: V360Spacing.s2),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: V360Spacing.s4,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _ColumnLabel(
                        label: widget.myLabel.toUpperCase(),
                        color: cs.primary,
                        alignEnd: false,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ColumnLabel(
                        label: widget.callerLabel.toUpperCase(),
                        color: cs.onSurfaceVariant,
                        alignEnd: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: V360Spacing.s2),
            ],
            Expanded(
              child: hasTranscript
                  ? _buildTranscriptList(context)
                  : _buildEmpty(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTranscriptList(BuildContext context) {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(
        V360Spacing.s4,
        V360Spacing.s2,
        V360Spacing.s4,
        V360Spacing.s8,
      ),
      itemCount: _transcript.turns.length,
      itemBuilder: (_, i) {
        final turn = _transcript.turns[i];
        return Container(
          key: _turnKeys[i],
          child: _TranscriptRow(
            turn: turn,
            isActive: i == _activeIndex,
            onTap: () => _onTurnTap(turn),
          ),
        );
      },
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return const V360EmptyState(
      icon: Icons.text_snippet_outlined,
      title: 'No transcript available',
      message: 'This call wasn\'t transcribed.',
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String summary;
  const _SummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(V360Spacing.s3),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(0.4),
        borderRadius: BorderRadius.circular(V360Radius.lg),
        border: Border.all(color: cs.primary.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome_rounded, color: cs.primary, size: 18),
          const SizedBox(width: V360Spacing.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SUMMARY',
                  style: tt.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  summary,
                  style: tt.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ColumnLabel extends StatelessWidget {
  final String label;
  final Color color;
  final bool alignEnd;
  const _ColumnLabel({
    required this.label,
    required this.color,
    required this.alignEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(V360Radius.full),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

class _TranscriptRow extends StatelessWidget {
  final TranscriptTurn turn;
  final bool isActive;
  final VoidCallback onTap;

  const _TranscriptRow({
    required this.turn,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isMine = turn.isAgent; // Map AGENT → left/blue (us), CUSTOMER → right.
    final bubbleColor = isActive
        ? cs.primary
        : (isMine ? cs.primaryContainer.withOpacity(0.5) : cs.surfaceContainer);
    final textColor = isActive ? cs.onPrimary : cs.onSurface;
    final timestamp = _formatTimestamp(turn.startSeconds);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: V360Spacing.s1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isMine ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          if (!isMine) const Spacer(),
          Flexible(
            flex: 5,
            child: Material(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(V360Radius.lg),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: V360Spacing.s3,
                    vertical: V360Spacing.s2,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            timestamp,
                            style: tt.labelSmall?.copyWith(
                              color: textColor.withOpacity(0.7),
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                            ),
                          ),
                          const Spacer(),
                          if (isActive)
                            Icon(Icons.graphic_eq_rounded,
                                size: 12, color: textColor),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        turn.text,
                        style: tt.bodyMedium?.copyWith(
                          color: textColor,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isMine) const Spacer(),
        ],
      ),
    );
  }

  String _formatTimestamp(double seconds) {
    if (seconds.isNaN || seconds < 0) return '0:00';
    final m = seconds ~/ 60;
    final s = (seconds % 60).toInt().toString().padLeft(2, '0');
    return '$m:$s';
  }
}
