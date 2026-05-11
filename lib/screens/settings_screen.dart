import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:itp_voice/cache/cache_service.dart';
import 'package:itp_voice/controllers/settings_controller.dart';
import 'package:itp_voice/design/v360.dart';
import 'package:itp_voice/repo/auth_repo.dart';
import 'package:itp_voice/routes.dart';

class SettingsScreen extends StatelessWidget {
  SettingsScreen({super.key});
  final SettingsController con = Get.put(SettingsController());

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: V360Spacing.s4,
          vertical: V360Spacing.s4,
        ),
        children: [
          _label('MY NUMBER'),
          const SizedBox(height: V360Spacing.s2),
          V360Card(
            padding: const EdgeInsets.symmetric(
              horizontal: V360Spacing.s4,
              vertical: V360Spacing.s3,
            ),
            child: Obx(() {
              return Row(
                children: [
                  Icon(Icons.phone_outlined, color: cs.primary, size: 20),
                  const SizedBox(width: V360Spacing.s3),
                  Expanded(
                    child: TextField(
                      controller: con.myNumberController,
                      enabled: con.isPhoneEditing.value,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (con.isPhoneEditing.value)
                    TextButton(
                      onPressed: () async {
                        await con.updateNumber();
                        con.isPhoneEditing.value = false;
                      },
                      child: const Text('Save'),
                    )
                  else
                    IconButton(
                      icon: Icon(Icons.edit_outlined, color: cs.primary),
                      onPressed: () => con.isPhoneEditing.value = true,
                    ),
                ],
              );
            }),
          ),
          const SizedBox(height: V360Spacing.s5),
          _label('APPEARANCE'),
          const SizedBox(height: V360Spacing.s2),
          V360Card(
            padding: const EdgeInsets.fromLTRB(
              V360Spacing.s4,
              V360Spacing.s4,
              V360Spacing.s4,
              V360Spacing.s4,
            ),
            child: Obx(() {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.dark_mode_outlined, color: cs.primary, size: 20),
                      const SizedBox(width: V360Spacing.s3),
                      const Text(
                        'Appearance',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: V360Spacing.s2),
                  Text(
                    'Follow the device theme, or pick a fixed look.',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: V360Spacing.s3),
                  SegmentedButton<AppThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: AppThemeMode.system,
                        label: Text('System'),
                        icon: Icon(Icons.phone_iphone_rounded, size: 16),
                      ),
                      ButtonSegment(
                        value: AppThemeMode.light,
                        label: Text('Light'),
                        icon: Icon(Icons.light_mode_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: AppThemeMode.dark,
                        label: Text('Dark'),
                        icon: Icon(Icons.dark_mode_outlined, size: 16),
                      ),
                    ],
                    selected: {con.themeMode.value},
                    onSelectionChanged: (s) => con.setThemeMode(s.first),
                    showSelectedIcon: false,
                  ),
                ],
              );
            }),
          ),
          const SizedBox(height: V360Spacing.s5),
          _label('ACCOUNT'),
          const SizedBox(height: V360Spacing.s2),
          V360Card(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _NavRow(
                  icon: Icons.lock_outline_rounded,
                  label: 'Change password',
                  onTap: () => Get.toNamed(Routes.CHANGE_PASSWORD_ROUTE),
                ),
                _Sep(),
                _NavRow(
                  icon: Icons.phone_callback_rounded,
                  label: 'Call settings',
                  onTap: () => Get.toNamed(Routes.CALL_SETTINGS_ROUTE),
                ),
              ],
            ),
          ),
          const SizedBox(height: V360Spacing.s5),
          V360Button(
            label: 'Log out',
            variant: V360ButtonVariant.danger,
            leadingIcon: Icons.logout_rounded,
            fullWidth: true,
            onPressed: () => _confirmLogout(context),
          ),
          const SizedBox(height: V360Spacing.s10),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You\'ll need to sign in again to make calls.'),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: V360Colors.danger500),
            onPressed: () async {
              await AuthRepo().logoutUser();
              await AppCache.instance.clearAll();
              Get.offAllNamed(Routes.LOGIN_SCREEN_ROUTE);
            },
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(left: V360Spacing.s2),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      );
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
            Icon(Icons.chevron_right_rounded,
                color: cs.onSurfaceVariant, size: 22),
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
