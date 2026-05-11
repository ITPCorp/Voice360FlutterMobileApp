import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:itp_voice/controllers/profile_controller.dart';
import 'package:itp_voice/design/v360.dart';
import 'package:itp_voice/routes.dart';

class ProfileScreen extends StatelessWidget {
  ProfileScreen({super.key});
  final ProfileController con = Get.put(ProfileController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Get.toNamed(
              Routes.SETTINGS_SCREEN_ROUTE,
              arguments: con.mobileController.text,
            ),
          ),
        ],
      ),
      body: Obx(() {
        if (con.isloading.value && con.userProfile == null) {
          return const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => con.fetchUserProfile(),
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: V360Spacing.s4,
              vertical: V360Spacing.s4,
            ),
            children: [
              _ProfileHeader(con: con),
              const SizedBox(height: V360Spacing.s6),
              _SectionLabel(text: 'ACCOUNT'),
              const SizedBox(height: V360Spacing.s2),
              V360Card(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _Row(
                      icon: Icons.alternate_email_rounded,
                      label: 'Email',
                      value: con.emailController.text,
                    ),
                    const _Sep(),
                    _Row(
                      icon: Icons.phone_iphone_rounded,
                      label: 'Mobile',
                      value: con.mobileController.text.isEmpty
                          ? '—'
                          : con.mobileController.text,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: V360Spacing.s5),
              _SectionLabel(text: 'PREFERENCES'),
              const SizedBox(height: V360Spacing.s2),
              V360Card(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _NavRow(
                      icon: Icons.tune_rounded,
                      label: 'Settings',
                      onTap: () => Get.toNamed(
                        Routes.SETTINGS_SCREEN_ROUTE,
                        arguments: con.mobileController.text,
                      ),
                    ),
                    const _Sep(),
                    _NavRow(
                      icon: Icons.phone_callback_rounded,
                      label: 'Call settings',
                      onTap: () =>
                          Get.toNamed(Routes.CALL_SETTINGS_ROUTE),
                    ),
                    const _Sep(),
                    _NavRow(
                      icon: Icons.lock_outline_rounded,
                      label: 'Change password',
                      onTap: () =>
                          Get.toNamed(Routes.CHANGE_PASSWORD_ROUTE),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: V360Spacing.s10),
            ],
          ),
        );
      }),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final ProfileController con;
  const _ProfileHeader({required this.con});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final name = con.nameController.text.trim();
    final email = con.emailController.text.trim();
    return V360Card(
      padding: const EdgeInsets.all(V360Spacing.s5),
      child: Row(
        children: [
          V360Avatar(name: name.isEmpty ? '?' : name, size: 64),
          const SizedBox(width: V360Spacing.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? '(No name)' : name,
                  style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: V360Spacing.s2),
      child: Text(
        text,
        style: TextStyle(
          color: cs.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _Row({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: V360Spacing.s4,
        vertical: V360Spacing.s3,
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.primary, size: 20),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _NavRow({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: V360Spacing.s4,
          vertical: V360Spacing.s4,
        ),
        child: Row(
          children: [
            Icon(icon, color: cs.primary, size: 20),
            const SizedBox(width: V360Spacing.s3),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: cs.onSurfaceVariant,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep();
  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        color: Theme.of(context).colorScheme.outlineVariant,
        indent: 56,
      );
}
