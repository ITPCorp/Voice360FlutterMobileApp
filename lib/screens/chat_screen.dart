import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:itp_voice/controllers/base_screen_controller.dart';
import 'package:itp_voice/controllers/chat_controller.dart';
import 'package:itp_voice/design/v360.dart';
import 'package:itp_voice/models/get_thread_messages_response_model/get_thread_messages_response_model.dart';
import 'package:itp_voice/routes.dart';
import 'package:itp_voice/screens/transcript_modal.dart';
import 'package:itp_voice/services/call_media.dart';
import 'package:itp_voice/services/contact_resolver.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  // Force-replace the controller on every screen mount so a re-navigation
  // (eg. from a notification tap landing on a different thread) re-runs
  // onInit and re-parses Get.arguments. Without this, GetX silently
  // returns the prior thread's controller and the screen renders the
  // stale conversation.
  late final ChatController con = _freshController();
  final BaseScreenController base = Get.find<BaseScreenController>();
  final ScrollController _scroll = ScrollController();

  ChatController _freshController() {
    if (Get.isRegistered<ChatController>()) {
      Get.delete<ChatController>(force: true);
    }
    return Get.put(ChatController());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String _peerNumber() {
    final ps = con.messages?.result?.participants ?? [];
    final p = ps.firstWhere(
      (x) => x.isSelf != true,
      orElse: () => ps.isEmpty ? Participants() : ps.first,
    );
    return p.number ?? con.threadNumber ?? 'Unknown';
  }

  /// Return the embedded `participant.contact` for the peer of this thread,
  /// or `null` if the server didn't attach one. Used to pass through to the
  /// (i) info screen so it doesn't depend on the local contacts cache.
  ParticipantContact? _participantContact() {
    final ps = con.messages?.result?.participants ?? const [];
    for (final p in ps) {
      if (p.isSelf == true) continue;
      if (p.contact != null) return p.contact;
    }
    return null;
  }

  String _peerDisplay() {
    // 1. If this chat was opened from a contact tap, use that contact's name.
    final c = con.contact;
    if (c != null) {
      final name = ('${c.firstname ?? ''} ${c.lastname ?? ''}').trim();
      if (name.isNotEmpty) return name;
    }
    // 2. Otherwise prefer the participant.contact the server embedded.
    final ps = con.messages?.result?.participants ?? const [];
    for (final p in ps) {
      if (p.isSelf == true) continue;
      final embedded = p.contactName;
      if (embedded != null && embedded.isNotEmpty) return embedded;
    }
    // 3. Fall back to a local cache lookup by phone number.
    final peer = _peerNumber();
    final fromCache = ContactResolver.resolveNameOrNull(peer);
    return fromCache ?? peer;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Obx(() {
          // Force re-render when loadTitle flips after participants populate.
          // ignore: unused_local_variable
          final _ = con.loadTitle.value;
          final display = _peerDisplay();
          final number = _peerNumber();
          final showNumber = display != number;
          return Row(
            children: [
              V360Avatar(name: display, size: 36),
              const SizedBox(width: V360Spacing.s2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      display,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      showNumber ? number : 'SMS · From ${con.myNumber}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          );
        }),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_rounded, color: V360Colors.callAccept),
            tooltip: 'Call',
            onPressed: () => base.handleCall(_peerNumber(), context),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            tooltip: 'Conversation info',
            onPressed: () => Get.toNamed(
              Routes.CHAT_DETAIL_ROUTE,
              // Pass both the peer number AND any participant.contact we
              // already have from the threads list. The (i) controller would
              // otherwise only know about contacts in the local cache, and
              // the cache is limited to the contact pages the user has
              // scrolled through.
              arguments: {
                'phone': _peerNumber(),
                'participantContact': _participantContact(),
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Obx(() {
              final messages = con.messages?.result?.messages ?? [];
              // Show the loading spinner whenever a fetch is in flight AND
              // there's nothing to render yet. This catches the case where
              // we've seeded participants from the threads list (so
              // _messages.value isn't null) but the actual message history
              // hasn't loaded from disk or the server.
              if (con.isLoading.value && messages.isEmpty) {
                return const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                );
              }
              if (messages.isEmpty) {
                // Only show the "new conversation" empty state when we're
                // not in the middle of a fetch AND there's truly nothing.
                final compose = con.isCompose;
                return V360EmptyState(
                  icon: compose
                      ? Icons.edit_square
                      : Icons.chat_bubble_outline_rounded,
                  title: compose ? 'New conversation' : 'No messages yet',
                  message: compose
                      ? 'Type your first message below to start chatting.'
                      : 'Start the conversation below.',
                );
              }
              return ListView.builder(
                controller: _scroll,
                reverse: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: V360Spacing.s4,
                  vertical: V360Spacing.s4,
                ),
                itemCount: messages.length,
                itemBuilder: (_, i) {
                  final m = messages[i];
                  final next = i + 1 < messages.length ? messages[i + 1] : null;
                  final isMe = m.messageParticipant == con.myNumber ||
                      (m.messageParticipant != null &&
                          m.messageParticipant ==
                              con.messages?.result?.participants
                                  ?.firstWhere(
                                    (p) => p.isSelf == true,
                                    orElse: () => Participants(),
                                  )
                                  .number);
                  final showTimestamp =
                      next == null || _shouldShowTimestamp(m, next);
                  if (m.isCall) {
                    return _CallTimelineEntry(
                      message: m,
                      isMe: isMe,
                      showTimestamp: showTimestamp,
                      peerDisplay: _peerDisplay(),
                    );
                  }
                  return _MessageBubble(
                    message: m,
                    isMe: isMe,
                    showTimestamp: showTimestamp,
                  );
                },
              );
            }),
          ),
          _Composer(controller: con),
        ],
      ),
    );
  }

  bool _shouldShowTimestamp(Messages a, Messages b) {
    final at = DateTime.tryParse(a.messageTimestamp ?? '');
    final bt = DateTime.tryParse(b.messageTimestamp ?? '');
    if (at == null || bt == null) return false;
    return at.difference(bt).inMinutes.abs() > 30;
  }
}

class _MessageBubble extends StatelessWidget {
  final Messages message;
  final bool isMe;
  final bool showTimestamp;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.showTimestamp,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(V360Radius.xl),
      topRight: const Radius.circular(V360Radius.xl),
      bottomLeft: Radius.circular(isMe ? V360Radius.xl : 4),
      bottomRight: Radius.circular(isMe ? 4 : V360Radius.xl),
    );
    final bg = isMe ? cs.primary : cs.surfaceContainer;
    final fg = isMe ? cs.onPrimary : cs.onSurface;
    final body = (message.messageBody ?? '').trim();
    final hasMedia = message.messageMmsMedia != null &&
        message.messageMmsMedia.toString().isNotEmpty &&
        message.messageMmsMedia.toString() != 'null';

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showTimestamp)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: V360Spacing.s3),
              child: Center(
                child: Text(
                  _formatTimestamp(message.messageTimestamp),
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            child: Material(
              color: bg,
              borderRadius: radius,
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: V360Spacing.s4,
                  vertical: V360Spacing.s3,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasMedia)
                      Padding(
                        padding: EdgeInsets.only(bottom: body.isEmpty ? 0 : V360Spacing.s2),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(V360Radius.lg),
                          child: Image.network(
                            message.messageMmsMedia.toString(),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              padding: const EdgeInsets.all(V360Spacing.s4),
                              color: cs.surfaceContainerHigh,
                              child: const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                      ),
                    if (body.isNotEmpty)
                      Text(
                        body,
                        style: tt.bodyLarge?.copyWith(color: fg),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (isMe && message.isDelivered == true)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 4),
              child: Text(
                'Delivered',
                style: tt.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatTimestamp(String? iso) {
    final t = DateTime.tryParse(iso ?? '')?.toLocal();
    if (t == null) return '';
    final hh = t.hour > 12 ? t.hour - 12 : (t.hour == 0 ? 12 : t.hour);
    final mm = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour >= 12 ? 'PM' : 'AM';
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '$hh:$mm $ampm';
    }
    return '${t.month}/${t.day} · $hh:$mm $ampm';
  }
}

class _Composer extends StatelessWidget {
  final ChatController controller;
  const _Composer({required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        padding: const EdgeInsets.fromLTRB(
          V360Spacing.s3,
          V360Spacing.s2,
          V360Spacing.s3,
          V360Spacing.s2,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FromNumberRow(controller: controller),
            const SizedBox(height: V360Spacing.s2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  icon: Icon(Icons.image_outlined, color: cs.onSurfaceVariant),
                  onPressed: () => controller.sendMessage(isImage: true),
                  tooltip: 'Attach image',
                ),
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 140),
                    child: TextField(
                      controller: controller.messageController,
                      minLines: 1,
                      maxLines: 6,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Message',
                        filled: true,
                        fillColor: cs.surfaceContainer,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: V360Spacing.s4,
                          vertical: V360Spacing.s3,
                        ),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(V360Radius.xxl),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(V360Radius.xxl),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(V360Radius.xxl),
                          borderSide: BorderSide(color: cs.primary, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: V360Spacing.s2),
                _SendButton(onTap: controller.sendMessage),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FromNumberRow extends StatelessWidget {
  final ChatController controller;
  const _FromNumberRow({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final available = controller.availableFromNumbers;
      if (available.length <= 1) {
        // Single number — show a static "From" badge, no picker. Hidden
        // entirely if user only has one number AND we're in thread mode.
        if (controller.isCompose && available.isNotEmpty) {
          return _StaticFromBadge(number: available.first);
        }
        return const SizedBox.shrink();
      }
      return _FromPicker(
        current: controller.myNumber.isNotEmpty
            ? controller.myNumber
            : available.first,
        options: available,
        onChanged: controller.changeFromNumber,
      );
    });
  }
}

class _StaticFromBadge extends StatelessWidget {
  final String number;
  const _StaticFromBadge({required this.number});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: V360Spacing.s1, bottom: 2),
      child: Row(
        children: [
          Icon(Icons.outbox_outlined, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            'From $number',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _FromPicker extends StatelessWidget {
  final String current;
  final List<String> options;
  final void Function(String) onChanged;
  const _FromPicker({
    required this.current,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: V360Spacing.s3,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(V360Radius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.outbox_outlined, size: 16, color: cs.primary),
          const SizedBox(width: V360Spacing.s2),
          Text(
            'From',
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: V360Spacing.s2),
          Expanded(
            child: DropdownButton<String>(
              value: options.contains(current) ? current : options.first,
              isDense: true,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
              icon: Icon(
                Icons.unfold_more_rounded,
                size: 16,
                color: cs.onSurfaceVariant,
              ),
              items: [
                for (final n in options)
                  DropdownMenuItem(value: n, child: Text(n)),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SendButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: V360Colors.primary500,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

/// A call entry in the chat timeline — distinct visual treatment from SMS
/// bubbles. Shows direction/status, duration, an inline compact audio
/// player when a recording exists, and a "View transcript" pill that opens
/// the [TranscriptModal].
class _CallTimelineEntry extends StatelessWidget {
  final Messages message;
  final bool isMe;
  final bool showTimestamp;
  final String peerDisplay;

  const _CallTimelineEntry({
    required this.message,
    required this.isMe,
    required this.showTimestamp,
    required this.peerDisplay,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final missed =
        (message.callStatus ?? '').contains('missed');
    final answered =
        (message.callStatus ?? '').contains('answered');
    final inbound = (message.callDirection ?? 'inbound') != 'outbound';
    final aiCall = message.aiCall;

    final IconData icon;
    if (missed) {
      icon = Icons.call_missed_rounded;
    } else if (aiCall) {
      icon = Icons.smart_toy_rounded;
    } else if (inbound) {
      icon = Icons.call_received_rounded;
    } else {
      icon = Icons.call_made_rounded;
    }

    final Color iconColor = missed
        ? V360Colors.callMissed
        : aiCall
            ? V360Colors.primary500
            : (inbound ? V360Colors.success500 : V360Colors.primary500);

    final label = _buildLabel(missed, answered, inbound, aiCall);

    final hasRecording = message.hasRecording;
    final hasTranscript = message.hasTranscript;
    final recordingUrl = hasRecording ? CallMedia.recordingUrl(message.cdrPk) : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: V360Spacing.s2),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: V360Spacing.s3,
              vertical: V360Spacing.s3,
            ),
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.circular(V360Radius.lg),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: iconColor.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(icon, size: 16, color: iconColor),
                    ),
                    const SizedBox(width: V360Spacing.s2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: tt.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: missed
                                  ? V360Colors.callMissed
                                  : cs.onSurface,
                            ),
                          ),
                          if (message.callDuration != null &&
                              message.callDuration! > 0)
                            Text(
                              _formatDuration(message.callDuration!),
                              style: tt.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (showTimestamp)
                      Text(
                        _formatRelative(message.messageTimestamp),
                        style: tt.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
                if (hasRecording && recordingUrl != null) ...[
                  const SizedBox(height: V360Spacing.s3),
                  V360AudioPlayer.compact(
                    url: recordingUrl,
                    filename:
                        'call-${message.cdrPk ?? message.pk ?? "recording"}.wav',
                    durationSeconds: message.callDuration,
                  ),
                ],
                if (hasTranscript) ...[
                  const SizedBox(height: V360Spacing.s3),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _TranscriptPill(
                      onTap: () => _openTranscript(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _buildLabel(bool missed, bool answered, bool inbound, bool aiCall) {
    if (missed) return 'Missed call';
    if (aiCall) return 'Call handled by AI';
    if (answered) {
      return inbound ? 'Inbound call' : 'Outbound call';
    }
    return inbound ? 'Inbound call' : 'Outbound call';
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  String _formatRelative(String? iso) {
    if (iso == null) return '';
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return '';
    final hh = t.hour > 12 ? t.hour - 12 : (t.hour == 0 ? 12 : t.hour);
    final mm = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour >= 12 ? 'PM' : 'AM';
    return '$hh:$mm $ampm';
  }

  void _openTranscript(BuildContext context) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => TranscriptModal(
          recordingUrl: message.hasRecording
              ? CallMedia.recordingUrl(message.cdrPk)
              : null,
          transcription: message.callTranscription,
          callerLabel: peerDisplay,
          myLabel: 'You',
          durationSeconds: message.callDuration,
          filename:
              'call-${message.cdrPk ?? message.pk ?? "recording"}.wav',
        ),
      ),
    );
  }
}

class _TranscriptPill extends StatelessWidget {
  final VoidCallback onTap;
  const _TranscriptPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primary.withOpacity(0.1),
      borderRadius: BorderRadius.circular(V360Radius.full),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: V360Spacing.s3,
            vertical: 6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.text_snippet_outlined,
                  size: 14, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                'View transcript',
                style: TextStyle(
                  color: cs.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
