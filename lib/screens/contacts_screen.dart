import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:itp_voice/controllers/base_screen_controller.dart';
import 'package:itp_voice/controllers/contacts_controller.dart';
import 'package:itp_voice/design/v360.dart';
import 'package:itp_voice/models/get_contacts_reponse_model/contact_response.dart';
import 'package:itp_voice/routes.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final ContactsController con = Get.put(ContactsController());
  final BaseScreenController base = Get.find<BaseScreenController>();
  final ScrollController _scroll = ScrollController();

  /// Debounce timer for the search field. ~280ms matches voice360-fe's
  /// perceived feel — fast enough to feel live, slow enough that we don't
  /// fire a request per keystroke.
  Timer? _searchDebounce;
  static const Duration _kSearchDebounce = Duration(milliseconds: 280);

  @override
  void initState() {
    super.initState();
    // Always refresh on open — cache hydration in the controller already gave
    // us something to render, so this call is silent (no shimmer flash).
    con.fetchContacts('0');
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 80 &&
          !con.isContactsLoading &&
          con.currentPage.value < con.totalPages.value &&
          con.searchController.text.trim().isEmpty) {
        // Only paginate the full list — when searching, the server returns
        // the full result page at once.
        con.fetchContacts(con.conOffSet.value.toString());
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onSearchChanged(String raw) {
    _searchDebounce?.cancel();
    final query = raw.trim();
    if (query.isEmpty) {
      // Empty → clear immediately, no debounce.
      con.clearSearch();
      setState(() {});
      return;
    }
    // Re-render so the instant client-side filter on existing data kicks
    // in while we wait for the server.
    setState(() {});
    _searchDebounce = Timer(_kSearchDebounce, () {
      if (!mounted) return;
      // Use the current text, not the captured `query`, in case the user kept
      // typing during the debounce window.
      final current = con.searchController.text.trim();
      if (current.isEmpty) {
        con.clearSearch();
      } else {
        con.searchContacts(current);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_rounded),
            onPressed: () => Get.toNamed(Routes.ADD_NEW_CONTACT_ROUTE),
            tooltip: 'Add contact',
          ),
        ],
      ),
      body: GetBuilder<ContactsController>(
        builder: (_) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  V360Spacing.s4,
                  V360Spacing.s2,
                  V360Spacing.s4,
                  V360Spacing.s3,
                ),
                child: V360SearchField(
                  controller: con.searchController,
                  hintText: 'Search contacts',
                  onChanged: _onSearchChanged,
                  onClear: () {
                    _searchDebounce?.cancel();
                    con.clearSearch();
                    setState(() {});
                  },
                ),
              ),
              Expanded(
                child: con.isContactsLoading && con.unfilteredData.isEmpty
                    ? const _ContactsLoading()
                    : _buildList(context),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final List<Contact> data = con.getDataList();
    if (data.isEmpty) {
      final isSearching = con.searchController.text.trim().isNotEmpty;
      if (isSearching) {
        if (con.isSearching) {
          // Server search in flight, nothing to render yet.
          return const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          );
        }
        return V360EmptyState(
          icon: Icons.search_off_rounded,
          title: 'No matches',
          message:
              'No contacts match "${con.searchController.text.trim()}".',
        );
      }
      return V360EmptyState(
        icon: Icons.people_alt_outlined,
        title: 'No contacts',
        message: 'Tap the + button to add your first contact.',
        action: V360Button(
          label: 'Add contact',
          leadingIcon: Icons.person_add_alt_1_rounded,
          onPressed: () => Get.toNamed(Routes.ADD_NEW_CONTACT_ROUTE),
        ),
      );
    }

    final isSearching = con.searchController.text.trim().isNotEmpty;

    final sorted = [...data]..sort((a, b) {
        final an =
            ('${a.firstname ?? ''} ${a.lastname ?? ''}').trim().toLowerCase();
        final bn =
            ('${b.firstname ?? ''} ${b.lastname ?? ''}').trim().toLowerCase();
        return an.compareTo(bn);
      });

    final List<Widget> items = [];
    // Skip A-Z section headers while searching — they add visual noise
    // when the list is small. Matches voice360-fe's behaviour (table-style
    // results, no grouping).
    String? lastLetter;
    for (final c in sorted) {
      final name = ('${c.firstname ?? ''} ${c.lastname ?? ''}').trim();
      if (!isSearching) {
        final letter = name.isEmpty ? '#' : name[0].toUpperCase();
        if (letter != lastLetter) {
          items.add(V360SectionHeader(title: letter));
          lastLetter = letter;
        }
      }
      items.add(_contactRow(c, name));
    }
    // Footer spinner — only on the full list. Searches return all matches in
    // one page, so there's no "load more" path.
    if (!isSearching && con.isContactsLoading) {
      items.add(const Padding(
        padding: EdgeInsets.all(V360Spacing.s4),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      ));
    }

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: V360Spacing.s10),
      children: items,
    );
  }

  Widget _contactRow(Contact c, String name) {
    return V360ListTile(
      leading: V360Avatar(name: name.isEmpty ? '?' : name, size: 44),
      title: name.isEmpty ? '(No name)' : name,
      subtitle: c.phone ?? c.email ?? '',
      trailing: IconButton(
        icon: const Icon(
          Icons.call_rounded,
          color: V360Colors.callAccept,
          size: 22,
        ),
        onPressed: c.phone == null || c.phone!.isEmpty
            ? null
            : () => base.handleCall(c.phone!, context),
      ),
      onTap: () {
        Get.toNamed(
          Routes.CONTACT_DETAIS_SCREEN_ROUTE,
          arguments: {'contact': c},
        );
      },
    );
  }
}

class _ContactsLoading extends StatelessWidget {
  const _ContactsLoading();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 10,
      padding: const EdgeInsets.symmetric(horizontal: V360Spacing.s4),
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(vertical: V360Spacing.s2),
        child: Row(
          children: [
            V360Skeleton.circle(size: 44),
            const SizedBox(width: V360Spacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  V360Skeleton.line(width: 160, height: 14),
                  const SizedBox(height: 6),
                  V360Skeleton.line(width: 100, height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
