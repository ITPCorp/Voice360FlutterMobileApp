import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:itp_voice/controllers/messages_controller.dart';
import 'package:itp_voice/design/v360.dart';
import 'package:itp_voice/models/get_message_threads_response_model/get_message_threads_response_model.dart';
import 'package:itp_voice/routes.dart';
import 'package:itp_voice/services/contact_resolver.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final MessagesController con = Get.put(MessagesController());
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Trigger when the user is within ~300px of the bottom — feels smoother
    // than waiting until they hit the floor.
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 300 &&
        con.hasMore &&
        !con.isLoadingMore.value &&
        !con.isloading.value &&
        con.searchController.text.trim().isEmpty) {
      con.loadMoreThreads();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_square),
            tooltip: 'New message',
            onPressed: () => con.sendNewMessage(context),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildNumberSelector(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              V360Spacing.s4,
              V360Spacing.s2,
              V360Spacing.s4,
              V360Spacing.s3,
            ),
            child: V360SearchField(
              controller: con.searchController,
              hintText: 'Search conversations',
              onChanged: (_) => con.filterThreads(),
              onClear: () {
                con.searchController.clear();
                con.filterThreads();
              },
            ),
          ),
          Expanded(
            child: Obx(() {
              if (con.isloading.value && con.threads.isEmpty) {
                return const _ThreadsLoading();
              }
              if (con.threads.isEmpty) {
                return V360EmptyState(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'No conversations',
                  message: 'Tap the pencil icon to start a new message.',
                  action: V360Button(
                    label: 'New message',
                    leadingIcon: Icons.edit_square,
                    onPressed: () => con.sendNewMessage(context),
                  ),
                );
              }
              final isSearching =
                  con.searchController.text.trim().isNotEmpty;
              // Only show the footer loader/spacer while showing the full
              // list (not filtered search results) and there's actually more
              // data to load.
              final showFooter = !isSearching && con.hasMore;
              final itemCount =
                  con.threads.length + (showFooter ? 1 : 0);
              return RefreshIndicator(
                onRefresh: () async => con.loadThreads(),
                child: ListView.separated(
                  controller: _scroll,
                  padding: const EdgeInsets.only(bottom: V360Spacing.s10),
                  itemCount: itemCount,
                  separatorBuilder: (_, i) {
                    // No divider above the footer slot.
                    if (showFooter && i == con.threads.length - 1) {
                      return const SizedBox.shrink();
                    }
                    return Divider(
                      height: 1,
                      color: Theme.of(context).colorScheme.outlineVariant,
                      indent: 76,
                    );
                  },
                  itemBuilder: (_, i) {
                    if (showFooter && i == con.threads.length) {
                      return const _LoadMoreFooter();
                    }
                    return _threadRow(con.threads[i]);
                  },
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberSelector(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Obx(() {
      if (con.numbers.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          V360Spacing.s4,
          V360Spacing.s3,
          V360Spacing.s4,
          0,
        ),
        child: V360Card(
          padding: const EdgeInsets.symmetric(
            horizontal: V360Spacing.s3,
            vertical: V360Spacing.s2,
          ),
          child: Row(
            children: [
              Icon(Icons.swap_horiz_rounded, color: cs.primary, size: 20),
              const SizedBox(width: V360Spacing.s2),
              Text(
                'From',
                style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: V360Spacing.s2),
              Expanded(
                child: DropdownButton<String>(
                  value: con.selectedNumber,
                  isDense: true,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final n in con.numbers)
                      DropdownMenuItem(value: n, child: Text(n)),
                  ],
                  onChanged: (v) {
                    con.selectedNumber = v;
                    con.loadThreads();
                  },
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _threadRow(MessageThreads t) {
    final other = t.participants
        ?.firstWhere((p) => p.isSelf != true,
            orElse: () => t.participants!.first)
        .number;
    final displayName = ContactResolver.resolveThreadDisplay(t);
    // When the display is a real name we show the phone number as the
    // sub-label of the row's title row; otherwise we just show the last
    // message (existing behaviour).
    final showSecondaryPhone =
        displayName != (other ?? 'Unknown') && (other ?? '').isNotEmpty;
    final unread = (t.unreadMessages ?? 0) > 0;
    return V360ListTile(
      leading: V360Avatar(name: displayName, size: 48),
      title: displayName,
      subtitle: showSecondaryPhone
          ? '${other!} · ${t.lastMessage ?? ''}'
          : (t.lastMessage ?? ''),
      titleStyle: TextStyle(
        fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
      ),
      subtitleMaxLines: 1,
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatRelative(t.lastUpdated),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: unread
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                ),
          ),
          const SizedBox(height: 4),
          if (unread)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 1,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(V360Radius.full),
              ),
              child: Text(
                t.unreadMessages.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
      onTap: () {
        // Pass the full MessageThreads object as a 4th arg so the chat
        // screen can render the contact name immediately, before the
        // thread-messages fetch returns (and even when offline).
        Get.toNamed(
          Routes.CHAT_SCREEN_ROUTE,
          arguments: [t.pk, con.selectedNumber, other, t],
        );
      },
    );
  }

  String _formatRelative(String? iso) {
    if (iso == null) return '';
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return '';
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    final hh = t.hour > 12 ? t.hour - 12 : (t.hour == 0 ? 12 : t.hour);
    final mm = t.minute.toString().padLeft(2, '0');
    return '${t.month}/${t.day} $hh:$mm';
  }
}

class _ThreadsLoading extends StatelessWidget {
  const _ThreadsLoading();
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 8,
      padding: const EdgeInsets.symmetric(horizontal: V360Spacing.s4),
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(vertical: V360Spacing.s3),
        child: Row(
          children: [
            V360Skeleton.circle(size: 48),
            const SizedBox(width: V360Spacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  V360Skeleton.line(width: 140, height: 14),
                  const SizedBox(height: 6),
                  V360Skeleton.line(width: 220, height: 12),
                ],
              ),
            ),
            V360Skeleton.line(width: 36, height: 10),
          ],
        ),
      ),
    );
  }
}

/// Footer row shown at the bottom of the thread list while older pages are
/// being fetched, or as a thin separator when an idle "load more" is queued.
class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter();

  @override
  Widget build(BuildContext context) {
    final con = Get.find<MessagesController>();
    return Obx(() {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: V360Spacing.s5),
        child: Center(
          child: con.isLoadingMore.value
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation(
                        Theme.of(context).colorScheme.primary),
                  ),
                )
              : const SizedBox(height: 22),
        ),
      );
    });
  }
}
