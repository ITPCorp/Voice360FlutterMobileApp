import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:itp_voice/controllers/base_screen_controller.dart';
import 'package:itp_voice/controllers/call_history_controller.dart';
import 'package:itp_voice/design/v360.dart';
import 'package:itp_voice/models/call_history_model.dart';
import 'package:itp_voice/screens/transcript_modal.dart';
import 'package:itp_voice/services/call_media.dart';

enum _Filter { all, missed, inbound, outbound }

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  final CallHistoryController con = Get.put(CallHistoryController());
  final BaseScreenController base = Get.find<BaseScreenController>();
  _Filter _filter = _Filter.all;

  bool _matchesFilter(CallHistory c) {
    final missed = (c.isMissed ?? false) && (c.isIncoming ?? false);
    final inbound = (c.isIncoming ?? false) && !missed;
    final outbound = !(c.isIncoming ?? true);
    return switch (_filter) {
      _Filter.all => true,
      _Filter.missed => missed,
      _Filter.inbound => inbound,
      _Filter.outbound => outbound,
    };
  }

  bool _matchesSearch(CallHistory c, String q) {
    if (q.isEmpty) return true;
    final n = (c.name ?? '').toLowerCase();
    final num = (c.numberToDial ?? '').toLowerCase();
    return n.contains(q) || num.contains(q);
  }

  Iterable<CallHistory> _apply(List<CallHistory>? src) {
    if (src == null) return const [];
    final q = con.searchController.text.toLowerCase().trim();
    return src.where((c) => _matchesFilter(c) && _matchesSearch(c, q));
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<CallHistoryController>(
      builder: (_) {
        return Column(
          children: [
            _buildSearchAndFilters(context),
            Expanded(
              child: con.isLoading && con.callHistoryList.isEmpty
                  ? const _CallHistoryLoading()
                  : _buildList(context),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearchAndFilters(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V360Spacing.s4,
        V360Spacing.s3,
        V360Spacing.s4,
        V360Spacing.s3,
      ),
      child: Column(
        children: [
          V360SearchField(
            controller: con.searchController,
            hintText: 'Search calls',
            onChanged: (_) => con.update(),
            onClear: () {
              con.searchController.clear();
              con.update();
            },
          ),
          const SizedBox(height: V360Spacing.s3),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('All', _Filter.all),
                const SizedBox(width: V360Spacing.s2),
                _filterChip('Missed', _Filter.missed),
                const SizedBox(width: V360Spacing.s2),
                _filterChip('Inbound', _Filter.inbound),
                const SizedBox(width: V360Spacing.s2),
                _filterChip('Outbound', _Filter.outbound),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, _Filter f) {
    final selected = _filter == f;
    final cs = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = f),
      labelStyle: TextStyle(
        color: selected ? cs.onPrimary : cs.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      backgroundColor: cs.surfaceContainer,
      selectedColor: cs.primary,
      side: BorderSide(
        color: selected ? cs.primary : cs.outlineVariant,
      ),
      padding: const EdgeInsets.symmetric(horizontal: V360Spacing.s2),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildList(BuildContext context) {
    final today = _apply(con.todayCallHistory).toList();
    final yesterday = _apply(con.yesterdayCallHistory).toList();
    final earlier = _apply(con.callHistoryList).toList();

    if (today.isEmpty && yesterday.isEmpty && earlier.isEmpty) {
      return const V360EmptyState(
        icon: Icons.call_outlined,
        title: 'No calls yet',
        message: 'Your call history will appear here.',
      );
    }

    return ListView(
      controller: con.scrollController,
      padding: const EdgeInsets.only(bottom: V360Spacing.s10),
      children: [
        if (today.isNotEmpty) ...[
          const V360SectionHeader(title: 'TODAY'),
          ...today.map((c) => _row(context, c)),
        ],
        if (yesterday.isNotEmpty) ...[
          const V360SectionHeader(title: 'YESTERDAY'),
          ...yesterday.map((c) => _row(context, c)),
        ],
        if (earlier.isNotEmpty) ...[
          const V360SectionHeader(title: 'EARLIER'),
          ...earlier.map((c) => _row(context, c)),
        ],
        if (con.isLoading && con.callHistoryList.isNotEmpty)
          const Padding(
            padding: EdgeInsets.all(V360Spacing.s4),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          ),
      ],
    );
  }

  Widget _row(BuildContext context, CallHistory c) {
    final missed = (c.isMissed ?? false) && (c.isIncoming ?? false);
    final inbound = c.isIncoming ?? false;

    final IconData icon = missed
        ? Icons.call_missed_rounded
        : inbound
            ? Icons.call_received_rounded
            : Icons.call_made_rounded;
    final Color iconColor = missed
        ? V360Colors.callMissed
        : inbound
            ? V360Colors.success500
            : V360Colors.primary500;

    final name = (c.name ?? '').isNotEmpty
        ? c.name!
        : (c.numberToDial ?? 'Unknown');
    final subtitle = (c.name ?? '').isNotEmpty
        ? c.numberToDial ?? ''
        : '';
    final time = _formatTime(c.time);

    final hasMedia = c.hasRecording || c.hasTranscript;
    return V360ListTile(
      leading: V360Avatar(name: name, size: 44),
      title: name,
      subtitle: '${_typeLabel(missed: missed, inbound: inbound)}'
          '${subtitle.isNotEmpty ? ' • $subtitle' : ''}'
          '${(c.duration != null && c.duration! > 0) ? ' • ${_formatDuration(c.duration!)}' : ''}',
      titleStyle: TextStyle(
        fontWeight: FontWeight.w600,
        color: missed ? V360Colors.callMissed : null,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasMedia)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color:
                      Theme.of(context).colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(V360Radius.full),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      c.hasTranscript
                          ? Icons.text_snippet_outlined
                          : Icons.graphic_eq_rounded,
                      size: 11,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    if (c.hasTranscript && c.hasRecording) ...[
                      const SizedBox(width: 2),
                      Icon(
                        Icons.graphic_eq_rounded,
                        size: 11,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (time.isNotEmpty)
            Text(
              time,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          const SizedBox(width: V360Spacing.s2),
          Icon(icon, color: iconColor, size: 20),
        ],
      ),
      onTap: () => _onTapRow(context, c),
      onLongPress: c.numberToDial == null || c.numberToDial!.isEmpty
          ? null
          : () => base.handleCall(c.numberToDial!, context),
    );
  }

  void _onTapRow(BuildContext context, CallHistory c) {
    final hasMedia = c.hasRecording || c.hasTranscript;
    if (!hasMedia) {
      // No recording / transcript — preserve the old behaviour (tap to call).
      if (c.numberToDial != null && c.numberToDial!.isNotEmpty) {
        base.handleCall(c.numberToDial!, context);
      }
      return;
    }
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheetCtx) {
        final name = (c.name ?? '').isNotEmpty
            ? c.name!
            : (c.numberToDial ?? 'Unknown');
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: V360Avatar(name: name, size: 36),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${_typeLabel(missed: (c.isMissed ?? false) && (c.isIncoming ?? false), inbound: c.isIncoming ?? false)}'
                  '${(c.duration != null && c.duration! > 0) ? ' • ${_formatDuration(c.duration!)}' : ''}',
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.call_rounded,
                    color: V360Colors.callAccept),
                title: const Text('Call back'),
                enabled:
                    c.numberToDial != null && c.numberToDial!.isNotEmpty,
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  if (c.numberToDial != null && c.numberToDial!.isNotEmpty) {
                    base.handleCall(c.numberToDial!, context);
                  }
                },
              ),
              ListTile(
                leading: Icon(Icons.text_snippet_outlined,
                    color: Theme.of(context).colorScheme.primary),
                title: const Text('Recording & transcript'),
                subtitle: Text(
                  [
                    if (c.hasRecording) 'Recording',
                    if (c.hasTranscript) 'Transcript',
                  ].join(' · '),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _openTranscriptModal(context, c);
                },
              ),
              const SizedBox(height: V360Spacing.s2),
            ],
          ),
        );
      },
    );
  }

  void _openTranscriptModal(BuildContext context, CallHistory c) {
    final name = (c.name ?? '').isNotEmpty
        ? c.name!
        : (c.numberToDial ?? 'Caller');
    final url = c.hasRecording ? CallMedia.recordingUrl(c.cdrPk) : null;
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => TranscriptModal(
          recordingUrl: url,
          transcription: c.callTranscription,
          callerLabel: name,
          myLabel: 'You',
          durationSeconds: c.duration,
          filename: 'call-${c.cdrPk ?? "recording"}.wav',
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}:${s.toString().padLeft(2, '0')}';
  }

  String _typeLabel({required bool missed, required bool inbound}) {
    if (missed) return 'Missed';
    if (inbound) return 'Inbound';
    return 'Outbound';
  }

  String _formatTime(DateTime? t) {
    if (t == null) return '';
    final hh = t.hour > 12 ? t.hour - 12 : (t.hour == 0 ? 12 : t.hour);
    final mm = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour >= 12 ? 'PM' : 'AM';
    return '$hh:$mm $ampm';
  }
}

class _CallHistoryLoading extends StatelessWidget {
  const _CallHistoryLoading();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 8,
      padding: const EdgeInsets.all(V360Spacing.s4),
      itemBuilder: (_, __) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: V360Spacing.s2),
          child: Row(
            children: [
              V360Skeleton.circle(size: 44),
              const SizedBox(width: V360Spacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    V360Skeleton.line(width: 140, height: 14),
                    const SizedBox(height: 6),
                    V360Skeleton.line(width: 90, height: 12),
                  ],
                ),
              ),
              V360Skeleton.line(width: 36, height: 12),
            ],
          ),
        );
      },
    );
  }
}
