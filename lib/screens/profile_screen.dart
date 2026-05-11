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
            onPressed: () => Get.toNamed(Routes.SETTINGS_SCREEN_ROUTE),
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
              const SizedBox(height: V360Spacing.s10),
            ],
          ),
        );
      }),
    );
  }
}

class _ProfileHeader extends StatefulWidget {
  final ProfileController con;
  const _ProfileHeader({required this.con});

  @override
  State<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends State<_ProfileHeader> {
  // 7-tap Android-style easter egg on the avatar to open the debug screen.
  int _avatarTaps = 0;
  DateTime? _firstTap;

  void _onAvatarTap() {
    final now = DateTime.now();
    if (_firstTap == null ||
        now.difference(_firstTap!) > const Duration(seconds: 5)) {
      _firstTap = now;
      _avatarTaps = 1;
      return;
    }
    _avatarTaps++;
    if (_avatarTaps >= 7) {
      _avatarTaps = 0;
      _firstTap = null;
      Get.toNamed(Routes.DEBUG_ROUTE);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final name = widget.con.nameController.text.trim();
    final email = widget.con.emailController.text.trim();
    return V360Card(
      padding: const EdgeInsets.all(V360Spacing.s5),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onAvatarTap,
            child: V360Avatar(name: name.isEmpty ? '?' : name, size: 64),
          ),
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

class _Sep extends StatelessWidget {
  const _Sep();
  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        color: Theme.of(context).colorScheme.outlineVariant,
        indent: 56,
      );
}
