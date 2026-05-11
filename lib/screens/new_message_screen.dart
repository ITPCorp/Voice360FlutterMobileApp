import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:itp_voice/controllers/contacts_controller.dart';
import 'package:itp_voice/design/v360.dart';
import 'package:itp_voice/models/get_contacts_reponse_model/contact_response.dart';
import 'package:itp_voice/routes.dart';

/// iMessage-style compose screen.
///
/// User types in the "To:" field. Contacts autocomplete from the live
/// contacts search; if the input looks like a phone number we also offer
/// a "Send to {number}" row so they can message arbitrary numbers.
///
/// Picking a result navigates to the chat screen in **compose mode**
/// (threadId=null). The chat controller will look up an existing thread
/// for that peer; if none exists it stays in compose mode and creates
/// one when the user hits send.
class NewMessageScreen extends StatefulWidget {
  const NewMessageScreen({super.key});

  @override
  State<NewMessageScreen> createState() => _NewMessageScreenState();
}

class _NewMessageScreenState extends State<NewMessageScreen> {
  final TextEditingController _to = TextEditingController();
  final FocusNode _focus = FocusNode();
  // ContactsController may not have been put yet if the user opens
  // compose before visiting the Contacts tab. Get.put is idempotent for
  // an existing instance, so this is safe either way.
  final ContactsController _contacts =
      Get.isRegistered<ContactsController>()
          ? Get.find<ContactsController>()
          : Get.put(ContactsController());
  Timer? _debounce;
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Autofocus when the screen settles so the keyboard pops without a tap.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _to.dispose();
    _focus.dispose();
    // Clear the search state so the contacts tab isn't left in search mode.
    _contacts.clearSearch();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    setState(() => _query = v.trim());
    if (_query.isEmpty) {
      _contacts.clearSearch();
      return;
    }
    // Don't fire server-side search for pure-digit input — those won't
    // match a name. The "Send to {number}" affordance handles digits.
    final isDigits = RegExp(r'^[\d\s\-\(\)\+]+$').hasMatch(_query);
    if (isDigits) {
      _contacts.clearSearch();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () {
      _contacts.searchContacts(_query);
    });
  }

  /// Strip everything except digits and a leading +.
  String _normalizeNumber(String raw) {
    final trimmed = raw.trim();
    final plus = trimmed.startsWith('+') ? '+' : '';
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    return '$plus$digits';
  }

  bool get _inputLooksLikeNumber {
    if (_query.isEmpty) return false;
    final digits = _query.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 7;
  }

  void _pickContact(Contact c) {
    if (c.phone == null || c.phone!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This contact has no phone number')),
      );
      return;
    }
    _openChat(peer: c.phone!, contact: c);
  }

  void _pickRawNumber() {
    final n = _normalizeNumber(_to.text);
    if (n.isEmpty) return;
    _openChat(peer: n);
  }

  void _openChat({required String peer, Contact? contact}) {
    HapticFeedback.selectionClick();
    // CHAT_SCREEN args: [threadId, peer/myNumber, peer-or-contact, ...]
    // Compose mode = threadId null. arg[1] is the peer in compose mode.
    Get.offNamed(
      Routes.CHAT_SCREEN_ROUTE,
      arguments: [null, peer, contact ?? peer],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Message'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Get.back(),
          tooltip: 'Cancel',
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toField(cs, tt),
            Divider(height: 1, color: cs.outlineVariant),
            Expanded(child: _results(cs, tt)),
          ],
        ),
      ),
    );
  }

  Widget _toField(ColorScheme cs, TextTheme tt) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        V360Spacing.s4,
        V360Spacing.s3,
        V360Spacing.s4,
        V360Spacing.s3,
      ),
      child: Row(
        children: [
          Text(
            'To:',
            style: tt.bodyLarge?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: V360Spacing.s3),
          Expanded(
            child: TextField(
              controller: _to,
              focusNode: _focus,
              autocorrect: false,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (_) {
                if (_inputLooksLikeNumber) _pickRawNumber();
              },
              style: tt.bodyLarge,
              decoration: InputDecoration(
                hintText: 'Name or phone number',
                border: InputBorder.none,
                isCollapsed: true,
                hintStyle: tt.bodyLarge?.copyWith(
                  color: cs.onSurfaceVariant.withOpacity(0.6),
                ),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.cancel_rounded, size: 20),
              color: cs.onSurfaceVariant,
              tooltip: 'Clear',
              onPressed: () {
                _to.clear();
                _onChanged('');
              },
            ),
        ],
      ),
    );
  }

  Widget _results(ColorScheme cs, TextTheme tt) {
    return GetBuilder<ContactsController>(
      builder: (con) {
        final query = _query;
        if (query.isEmpty) {
          // Empty state: nudge them to type, and show the full contact list
          // so they can pick directly without searching.
          final list = con.unfilteredData;
          if (list.isEmpty) {
            return _hint(cs, tt, 'Start typing to find a contact, or enter a phone number.');
          }
          return _contactList(list);
        }

        final isDigits = RegExp(r'^[\d\s\-\(\)\+]+$').hasMatch(query);
        if (isDigits) {
          // Pure-number input. Skip the loading state for digits since we
          // don't fire a server search; just offer the "Send to" row.
          return ListView(
            children: [
              if (_inputLooksLikeNumber) _sendToRow(),
            ],
          );
        }

        if (con.isSearching) {
          return const Center(child: CircularProgressIndicator());
        }

        // Contact search results (non-digit query)
        final results = con.getDataList();
        return _contactList(results, headerRow: _sendToRow(visible: _inputLooksLikeNumber));
      },
    );
  }

  Widget _hint(ColorScheme cs, TextTheme tt, String text) {
    return Padding(
      padding: const EdgeInsets.all(V360Spacing.s6),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _contactList(List<Contact> items, {Widget? headerRow}) {
    final hasHeader = headerRow != null;
    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: items.length + (hasHeader ? 1 : 0),
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: Theme.of(context).colorScheme.outlineVariant,
        indent: 76,
      ),
      itemBuilder: (_, i) {
        if (hasHeader && i == 0) return headerRow;
        final c = items[hasHeader ? i - 1 : i];
        return _contactTile(c);
      },
    );
  }

  Widget _contactTile(Contact c) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final name = [c.firstname, c.lastname]
        .where((s) => s != null && s.isNotEmpty)
        .join(' ')
        .trim();
    return InkWell(
      onTap: () => _pickContact(c),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: V360Spacing.s4,
          vertical: V360Spacing.s3,
        ),
        child: Row(
          children: [
            V360Avatar(name: name.isEmpty ? c.phone : name, size: 44),
            const SizedBox(width: V360Spacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? (c.phone ?? 'Unknown') : name,
                    style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (name.isNotEmpty && c.phone != null && c.phone!.isNotEmpty)
                    Text(
                      c.phone!,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sendToRow({bool visible = true}) {
    if (!visible) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final normalized = _normalizeNumber(_to.text);
    return InkWell(
      onTap: _pickRawNumber,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: V360Spacing.s4,
          vertical: V360Spacing.s3,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.dialpad_rounded,
                color: cs.onPrimaryContainer,
                size: 22,
              ),
            ),
            const SizedBox(width: V360Spacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Send to $normalized',
                    style: tt.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                  Text(
                    'New message',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: cs.onSurfaceVariant, size: 16),
          ],
        ),
      ),
    );
  }
}
