import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:itp_voice/controllers/base_screen_controller.dart';
import 'package:itp_voice/controllers/contacts_controller.dart';
import 'package:itp_voice/design/v360.dart';
import 'package:itp_voice/locator.dart';
import 'package:itp_voice/models/get_contacts_reponse_model/contact_response.dart';
import 'package:itp_voice/routes.dart';
import 'package:itp_voice/services/numbers_service.dart';
import 'package:itp_voice/services/threads_cache.dart';

class ContactDetailsScreen extends StatefulWidget {
  const ContactDetailsScreen({super.key});

  @override
  State<ContactDetailsScreen> createState() => _ContactDetailsScreenState();
}

class _ContactDetailsScreenState extends State<ContactDetailsScreen> {
  Contact? contact;
  final BaseScreenController base = Get.find<BaseScreenController>();
  final ContactsController con = Get.find<ContactsController>();

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    if (args is Map && args['contact'] is Contact) {
      contact = args['contact'] as Contact;
    } else if (args is Contact) {
      contact = args;
    }

    // Pre-warm the threads cache for the user's primary chat number so the
    // chat screen can answer "does a thread exist for this peer?" instantly
    // if the user taps Message. Fire-and-forget — no UI dependency.
    final myNumbers = locator<NumbersService>().chatNumbers;
    if (myNumbers.isNotEmpty) {
      locator<ThreadsCache>().warm(myNumbers.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final c = contact;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const V360EmptyState(
          icon: Icons.person_off_outlined,
          title: 'Contact not found',
        ),
      );
    }
    final fullName =
        ('${c.firstname ?? ''} ${c.lastname ?? ''}').trim();
    final displayName = fullName.isEmpty ? '(No name)' : fullName;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: cs.surface,
            foregroundColor: cs.onSurface,
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit',
                onPressed: () => Get.toNamed(
                  Routes.EDIT_CONTACT_ROUTE,
                  arguments: {'contact': c},
                ),
              ),
              IconButton(
                icon: const Icon(Icons.more_vert_rounded),
                tooltip: 'More',
                onPressed: () => _showActions(context, c),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      cs.primaryContainer,
                      cs.surface,
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: V360Spacing.s8),
                        V360Avatar(name: displayName, size: 96),
                        const SizedBox(height: V360Spacing.s3),
                        Text(
                          displayName,
                          style: tt.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(V360Spacing.s4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _quickAction(
                    icon: Icons.call_rounded,
                    label: 'Call',
                    color: V360Colors.callAccept,
                    onTap: c.phone == null || c.phone!.isEmpty
                        ? null
                        : () => base.handleCall(c.phone!, context),
                  ),
                  _quickAction(
                    icon: Icons.chat_bubble_rounded,
                    label: 'Message',
                    color: V360Colors.primary500,
                    onTap: c.phone == null || c.phone!.isEmpty
                        ? null
                        : () => Get.toNamed(
                              Routes.CHAT_SCREEN_ROUTE,
                              arguments: [null, c.phone, c],
                            ),
                  ),
                  _quickAction(
                    icon: Icons.mail_outline_rounded,
                    label: 'Email',
                    color: V360Colors.info500,
                    onTap: c.email == null || c.email!.isEmpty
                        ? null
                        : () {
                            // mail launcher hook — left to existing util
                          },
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: V360Spacing.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (c.phone != null && c.phone!.isNotEmpty)
                    _infoCard(
                      icon: Icons.phone_outlined,
                      label: 'Phone',
                      value: c.phone!,
                    ),
                  if (c.email != null && c.email!.isNotEmpty)
                    _infoCard(
                      icon: Icons.alternate_email_rounded,
                      label: 'Email',
                      value: c.email!,
                    ),
                  if (c.notes != null && c.notes!.isNotEmpty)
                    _infoCard(
                      icon: Icons.notes_rounded,
                      label: 'Notes',
                      value: c.notes!,
                      multiline: true,
                    ),
                  if ((c.address != null && c.address.toString().trim().isNotEmpty) ||
                      (c.city != null && c.city.toString().trim().isNotEmpty))
                    _infoCard(
                      icon: Icons.location_on_outlined,
                      label: 'Address',
                      value: [
                        if (c.address != null) c.address.toString(),
                        if (c.city != null) c.city.toString(),
                      ].where((s) => s.trim().isNotEmpty).join(', '),
                    ),
                  const SizedBox(height: V360Spacing.s10),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickAction({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: disabled ? color.withOpacity(0.25) : color,
              shape: BoxShape.circle,
              boxShadow: disabled
                  ? null
                  : [
                      BoxShadow(
                        color: color.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: V360Spacing.s2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: disabled
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String label,
    required String value,
    bool multiline = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: V360Spacing.s3),
      child: V360Card(
        onTap: multiline
            ? null
            : () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$label copied')),
                );
              },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(0.5),
                borderRadius: BorderRadius.circular(V360Radius.lg),
              ),
              child: Icon(icon, color: cs.primary, size: 18),
            ),
            const SizedBox(width: V360Spacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: tt.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: multiline ? 6 : 1,
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

  void _showActions(BuildContext context, Contact c) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: V360Spacing.s2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit contact'),
                  onTap: () {
                    Get.back();
                    Get.toNamed(
                      Routes.EDIT_CONTACT_ROUTE,
                      arguments: {'contact': c},
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded,
                      color: V360Colors.danger500),
                  title: const Text(
                    'Delete contact',
                    style: TextStyle(color: V360Colors.danger500),
                  ),
                  onTap: () => _confirmDelete(context, c),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, Contact c) {
    Get.back();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete contact?'),
        content:
            const Text('This will remove the contact from your account.'),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: V360Colors.danger500,
            ),
            onPressed: () {
              Get.back();
              con.deleteContact(c.pk);
              Get.back();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
