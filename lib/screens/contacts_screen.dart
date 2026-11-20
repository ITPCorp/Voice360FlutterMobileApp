import 'dart:async';

import 'package:flutter/material.dart';
import 'package:itp_voice/design/widgets/v360_live_list.dart';
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
              V360RefreshLine(
                  active: con.refreshing && con.unfilteredData.isNotEmpty),
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
        if (con.searchFailed) {
          return V360EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Could not search contacts',
            action: TextButton(
                onPressed: () =>
                    con.searchContacts(con.searchController.text.trim()),
                child: const Text('Try again')),
          );
        }
        return V360EmptyState(
          icon: Icons.search_off_rounded,
          title: 'No matches',
          message: 'No contacts match "${con.searchController.text.trim()}".',
        );
      }
      if (con.loadFailed) {
        return V360EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load contacts',
          message: 'Check your connection, then try again.',
          onRefresh: () => con.fetchContacts('0'),
          action: TextButton(
              onPressed: () => con.fetchContacts('0'),
              child: const Text('Try again')),
        );
      }
      return V360EmptyState(
        onRefresh: () => con.fetchContacts('0'),
        icon: Icons.people_alt_outlined,
        title: 'No contacts',
        action: V360Button(
          label: 'Add contact',
          leadingIcon: Icons.person_add_alt_1_rounded,
          onPressed: () => Get.toNamed(Routes.ADD_NEW_CONTACT_ROUTE),
        ),
      );
    }

    final isSearching = con.searchController.text.trim().isNotEmpty;

    final names = {
      for (final c in data)
        c: ('${c.firstname ?? ''} ${c.lastname ?? ''}').trim()
    };
    final sortNames = {
      for (final entry in names.entries) entry.key: entry.value.toLowerCase()
    };
    final sorted = [...data]
      ..sort((a, b) => sortNames[a]!.compareTo(sortNames[b]!));

    final rows = <Object>[];
    final ids = <Object>[];
    String? lastLetter;
    for (final c in sorted) {
      final name = names[c]!;
      final letter = name.isEmpty ? '#' : name[0].toUpperCase();
      if (!isSearching && letter != lastLetter) {
        rows.add(letter);
        ids.add('section $letter');
        lastLetter = letter;
      }
      rows.add(c);
      ids.add(c.pk ?? c);
    }
    final list = V360LiveList(
      key: ValueKey(con.searchController.text.trim()),
      controller: _scroll,
      cacheExtent: MediaQuery.sizeOf(context).height,
      ids: ids,
      padding: const EdgeInsets.only(bottom: V360Spacing.s10),
      itemBuilder: (_, i) {
        final item = rows[i];
        if (item is String) return V360SectionHeader(title: item);
        final c = item as Contact;
        return _contactRow(c, names[c]!);
      },
    );
    return isSearching
        ? list
        : RefreshIndicator(
            onRefresh: () => con.fetchContacts('0'), child: list);
  }

  Widget _contactRow(Contact c, String name) {
    return V360ListTile(
      leading: V360Avatar(name: name.isEmpty ? '?' : name, size: 44),
      title: name.isEmpty ? (c.phone ?? c.email ?? 'Contact') : name,
      subtitle: c.phone ?? c.email ?? '',
      trailing: IconButton(
        tooltip: 'Call contact',
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
