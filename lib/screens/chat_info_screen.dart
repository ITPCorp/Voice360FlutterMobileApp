import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:itp_voice/controllers/chat_info_controller.dart';
import 'package:itp_voice/design/v360.dart';
import 'package:itp_voice/routes.dart';

class ChatInfoScreen extends StatelessWidget {
  ChatInfoScreen({super.key});
  final ChatInfoController con = Get.put(ChatInfoController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conversation info')),
      body: Obx(() {
        // Re-read these every Obx rebuild so the view flips from "save new"
        // to "linked contact card" as soon as the server (or cache) gives
        // us a match.
        // ignore: unused_local_variable
        final loading = con.isLoading.value;
        final isLinked = con.isLinked;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(V360Spacing.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: V360Spacing.s4),
              _Header(con: con),
              const SizedBox(height: V360Spacing.s6),
              if (isLinked)
                _LinkedContactCard(con: con)
              else
                _SaveAsNewSection(con: con),
              const SizedBox(height: V360Spacing.s10),
            ],
          ),
        );
      }),
    );
  }
}

class _Header extends StatelessWidget {
  final ChatInfoController con;
  const _Header({required this.con});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final name = con.displayName();
    final showPhoneSubtitle = name != con.phone;
    return Column(
      children: [
        V360Avatar(name: name, size: 96),
        const SizedBox(height: V360Spacing.s3),
        Text(
          name,
          style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        if (showPhoneSubtitle) ...[
          const SizedBox(height: 2),
          Text(
            con.phone,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _LinkedContactCard extends StatelessWidget {
  final ChatInfoController con;
  const _LinkedContactCard({required this.con});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final c = con.linkedContact!;
    final email = c.email;
    final notes = c.notes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: V360Spacing.s3, vertical: V360Spacing.s3),
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(V360Radius.lg),
            border: Border.all(color: cs.primary.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle_rounded,
                  color: cs.primary, size: 18),
              const SizedBox(width: V360Spacing.s2),
              Expanded(
                child: Text(
                  'Linked to a saved contact',
                  style: tt.labelMedium?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: V360Spacing.s4),
        _InfoRow(
          icon: Icons.phone_outlined,
          label: 'Phone',
          value: c.phone ?? con.phone,
        ),
        if (email != null && email.isNotEmpty) ...[
          _InfoRow(
            icon: Icons.alternate_email_rounded,
            label: 'Email',
            value: email,
          ),
        ],
        if (notes != null && notes.isNotEmpty) ...[
          _InfoRow(
            icon: Icons.notes_rounded,
            label: 'Notes',
            value: notes,
            multiline: true,
          ),
        ],
        const SizedBox(height: V360Spacing.s5),
        V360Button(
          label: 'Open contact',
          leadingIcon: Icons.arrow_forward_rounded,
          fullWidth: true,
          size: V360ButtonSize.lg,
          onPressed: () {
            Get.toNamed(
              Routes.CONTACT_DETAIS_SCREEN_ROUTE,
              arguments: {'contact': c},
            );
          },
        ),
        const SizedBox(height: V360Spacing.s2),
        V360Button(
          label: 'Edit contact',
          variant: V360ButtonVariant.outline,
          leadingIcon: Icons.edit_outlined,
          fullWidth: true,
          onPressed: () {
            Get.toNamed(
              Routes.EDIT_CONTACT_ROUTE,
              arguments: {'contact': c},
            );
          },
        ),
      ],
    );
  }
}

class _SaveAsNewSection extends StatelessWidget {
  final ChatInfoController con;
  const _SaveAsNewSection({required this.con});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Save as new contact',
          style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: V360Spacing.s2),
        TextField(
          controller: con.fullNameController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Contact name',
            prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
          ),
        ),
        const SizedBox(height: V360Spacing.s5),
        if (con.isLoading.value)
          const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          )
        else
          V360Button(
            label: 'Save contact',
            leadingIcon: Icons.person_add_alt_1_rounded,
            fullWidth: true,
            size: V360ButtonSize.lg,
            onPressed: con.addContact,
          ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool multiline;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.multiline = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: V360Spacing.s2),
      child: V360Card(
        padding: const EdgeInsets.all(V360Spacing.s3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(0.5),
                borderRadius: BorderRadius.circular(V360Radius.lg),
              ),
              child: Icon(icon, color: cs.primary, size: 16),
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
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
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
}
