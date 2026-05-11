import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:itp_voice/cache/cache_service.dart';
import 'package:itp_voice/controllers/call_settings_controller.dart';
import 'package:itp_voice/controllers/settings_controller.dart';
import 'package:itp_voice/design/v360.dart';
import 'package:itp_voice/repo/auth_repo.dart';
import 'package:itp_voice/routes.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Unified Settings: appearance + call settings + account actions in one
/// place. The previous separate Call Settings sub-screen has been folded in.
class SettingsScreen extends StatelessWidget {
  SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsController settings = Get.put(SettingsController());
    final CallSettingsController call = Get.put(CallSettingsController());
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          Obx(() => call.isSaving.value
              ? const Padding(
                  padding: EdgeInsets.only(right: V360Spacing.s4),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : const SizedBox.shrink()),
        ],
      ),
      body: Obx(() {
        if (call.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: V360Spacing.s4,
            vertical: V360Spacing.s4,
          ),
          children: [
            _sectionLabel(context, 'APPEARANCE'),
            const SizedBox(height: V360Spacing.s2),
            _appearanceCard(context, settings),
            const SizedBox(height: V360Spacing.s6),
            _sectionLabel(context, 'CALL FORWARDING'),
            const SizedBox(height: V360Spacing.s2),
            _masterForwardCard(context, call),
            Obx(() => call.callForwarding.value
                ? Column(
                    children: [
                      const SizedBox(height: V360Spacing.s4),
                      _forwardSettingsCard(context, call),
                    ],
                  )
                : const SizedBox.shrink()),
            const SizedBox(height: V360Spacing.s6),
            _sectionLabel(context, 'CALLER ID'),
            const SizedBox(height: V360Spacing.s2),
            _callerIdCard(context, call),
            const SizedBox(height: V360Spacing.s6),
            _sectionLabel(context, 'CALL RECORDING'),
            const SizedBox(height: V360Spacing.s2),
            _recordingCard(context, call),
            const SizedBox(height: V360Spacing.s6),
            _sectionLabel(context, 'ACCOUNT'),
            const SizedBox(height: V360Spacing.s2),
            V360Card(
              padding: EdgeInsets.zero,
              child: _NavRow(
                icon: Icons.lock_outline_rounded,
                label: 'Change password',
                onTap: () => Get.toNamed(Routes.CHANGE_PASSWORD_ROUTE),
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
            const SizedBox(height: V360Spacing.s6),
            const _VersionFooter(),
            const SizedBox(height: V360Spacing.s6),
          ],
        );
      }),
    );
  }

  // ── Appearance ──────────────────────────────────────────────────────────
  Widget _appearanceCard(BuildContext context, SettingsController con) {
    final cs = Theme.of(context).colorScheme;
    return V360Card(
      padding: const EdgeInsets.all(V360Spacing.s4),
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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: V360Spacing.s2),
            Text(
              'Follow the device theme, or pick a fixed look.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
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
    );
  }

  // ── Call forwarding ─────────────────────────────────────────────────────
  Widget _masterForwardCard(BuildContext context, CallSettingsController con) {
    return V360Card(
      padding: const EdgeInsets.all(V360Spacing.s4),
      child: Obx(() => _SettingRow(
            iconBg: const Color(0xFFDBEAFE),
            iconColor: const Color(0xFF2563EB),
            icon: Icons.phone_forwarded_rounded,
            title: 'Enable Call Forwarding',
            description:
                'Enabling this option will forward any incoming calls to your user and will not ring any of your devices, including the web phone.',
            value: con.callForwarding.value,
            onChanged: con.toggleCallForwarding,
          )),
    );
  }

  Widget _forwardSettingsCard(BuildContext context, CallSettingsController con) {
    final cs = Theme.of(context).colorScheme;
    return V360Card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(
              V360Spacing.s4,
              V360Spacing.s4,
              V360Spacing.s4,
              V360Spacing.s3,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  cs.primaryContainer.withOpacity(0.5),
                  cs.tertiaryContainer.withOpacity(0.4),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Call Forward Settings',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Adjust the different options when forwarding a call',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(V360Spacing.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _IconHeader(
                  iconBg: const Color(0xFFDBEAFE),
                  iconColor: const Color(0xFF2563EB),
                  icon: Icons.info_outline_rounded,
                  title: 'Forward the call to:',
                  description:
                      'You can enter an extension number or a phone number to forward calls to',
                ),
                const SizedBox(height: V360Spacing.s3),
                TextField(
                  controller: con.forwardNumberController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    hintText: 'Enter extension or phone number',
                    prefixIcon: Icon(Icons.phone_rounded, size: 20),
                  ),
                  onSubmitted: (_) => con.saveForwardNumber(),
                  onEditingComplete: () => con.saveForwardNumber(),
                ),
                const SizedBox(height: V360Spacing.s4),
                Obx(() => _PillSettingRow(
                      icon: Icons.person_outline_rounded,
                      iconBg: const Color(0xFFDBEAFE),
                      iconColor: const Color(0xFF2563EB),
                      title: 'Keep Original Caller ID',
                      description:
                          "If enabled, this will show the caller's phone number on your screen. If disabled, the number that appears will either be the default caller ID or your customized outbound caller ID number.",
                      value: con.keepOriginalCallerId.value,
                      onChanged: con.toggleKeepOriginalCallerId,
                    )),
                const SizedBox(height: V360Spacing.s3),
                Obx(() => _PillSettingRow(
                      icon: Icons.groups_outlined,
                      iconBg: const Color(0xFFDBEAFE),
                      iconColor: const Color(0xFF2563EB),
                      title: 'Forward queue calls',
                      description:
                          'If enabled, any queues you are a member of will have calls forwarded. If disabled, queue calls will not be forwarded and will only ring your device or web phone.',
                      value: con.forwardQueueCalls.value,
                      onChanged: con.toggleForwardQueueCalls,
                    )),
                const SizedBox(height: V360Spacing.s3),
                Obx(() => _PillSettingRow(
                      icon: Icons.shield_outlined,
                      iconBg: const Color(0xFFDBEAFE),
                      iconColor: const Color(0xFF2563EB),
                      title: 'Call screening',
                      description:
                          'If enabled, when answering a forwarded call, a message will prompt you to accept the call or deny.',
                      value: con.callScreening.value,
                      onChanged: con.toggleCallScreening,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Caller ID ───────────────────────────────────────────────────────────
  Widget _callerIdCard(BuildContext context, CallSettingsController con) {
    return V360Card(
      padding: EdgeInsets.zero,
      child: Obx(() {
        final on = con.overrideDefaultCallerId.value;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(V360Spacing.s4),
              child: _SettingRow(
                iconBg: const Color(0xFFFEF3C7),
                iconColor: const Color(0xFFB45309),
                icon: Icons.badge_outlined,
                title: 'Override default Caller ID',
                description:
                    'Enabling this option will force your devices to use a specific phone number when placing a call.',
                value: on,
                onChanged: con.toggleOverrideDefaultCallerId,
              ),
            ),
            if (on)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  V360Spacing.s4,
                  0,
                  V360Spacing.s4,
                  V360Spacing.s4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _IconHeader(
                      iconBg: const Color(0xFFDBEAFE),
                      iconColor: const Color(0xFF2563EB),
                      icon: Icons.info_outline_rounded,
                      title: 'Caller ID Number',
                      description: 'Select the number to use for outbound calls',
                    ),
                    const SizedBox(height: V360Spacing.s3),
                    _callerIdNumberPicker(context, con),
                    if (con.hasOrphanedCallerId) ...[
                      const SizedBox(height: V360Spacing.s3),
                      _orphanedCallerIdWarning(),
                    ],
                    const SizedBox(height: V360Spacing.s4),
                    _IconHeader(
                      iconBg: const Color(0xFFDBEAFE),
                      iconColor: const Color(0xFF2563EB),
                      icon: Icons.info_outline_rounded,
                      title: 'Caller ID Name',
                      description:
                          'Type the name that appears when placing outbound calls',
                    ),
                    const SizedBox(height: V360Spacing.s3),
                    TextField(
                      controller: con.callerIdNameController,
                      maxLength: 15,
                      decoration: const InputDecoration(
                        hintText: 'Enter caller ID name',
                        prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                        counterText: 'Maximum 15 characters',
                      ),
                      onSubmitted: (_) => con.saveCallerIdName(),
                      onEditingComplete: () => con.saveCallerIdName(),
                    ),
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }

  Widget _callerIdNumberPicker(BuildContext context, CallSettingsController con) {
    final cs = Theme.of(context).colorScheme;
    return Obx(() {
      if (con.isLoadingNumbers.value && con.assignedNumbers.isEmpty) {
        return Container(
          padding: const EdgeInsets.all(V360Spacing.s4),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(0.4),
            borderRadius: BorderRadius.circular(V360Radius.lg),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: V360Spacing.s3),
              Text('Loading numbers…'),
            ],
          ),
        );
      }
      if (con.assignedNumbers.isEmpty && !con.hasOrphanedCallerId) {
        return Container(
          padding: const EdgeInsets.all(V360Spacing.s4),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(0.4),
            borderRadius: BorderRadius.circular(V360Radius.lg),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Text(
            'No numbers assigned to your extension.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        );
      }
      return InkWell(
        onTap: () => _showNumberPicker(context, con),
        borderRadius: BorderRadius.circular(V360Radius.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: V360Spacing.s4,
            vertical: V360Spacing.s3,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(V360Radius.lg),
          ),
          child: Row(
            children: [
              Icon(Icons.phone_outlined, color: cs.onSurfaceVariant, size: 20),
              const SizedBox(width: V360Spacing.s3),
              Expanded(
                child: Text(
                  _labelForSelected(con),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: con.hasOrphanedCallerId
                        ? const Color(0xFFDC2626)
                        : cs.onSurface,
                  ),
                ),
              ),
              Icon(Icons.expand_more_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      );
    });
  }

  String _labelForSelected(CallSettingsController con) {
    final num = con.selectedCallerIdNumber.value;
    if (num.isEmpty) return 'Select a number';
    final match =
        con.assignedNumbers.firstWhereOrNull((n) => n.number == num);
    if (match != null) return match.label;
    // Account-level default that isn't in the user's assigned numbers list —
    // valid inherited fallback, not an orphan.
    if (num == con.accountDefaultCallerIdNumber.value) {
      return '${AssignedNumber.formatPhone(num)} (Account default)';
    }
    return '${AssignedNumber.formatPhone(num)} (Number Not Available - Please Reassign)';
  }

  void _showNumberPicker(BuildContext context, CallSettingsController con) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: V360Spacing.s4,
              vertical: V360Spacing.s2,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: V360Spacing.s2,
                    vertical: V360Spacing.s2,
                  ),
                  child: Text(
                    'Choose outbound caller ID',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                Flexible(
                  child: Obx(() {
                    final acctNum = con.accountDefaultCallerIdNumber.value;
                    final hasAcctOption = acctNum.isNotEmpty &&
                        !con.assignedNumbers.any((n) => n.number == acctNum);
                    final items = <AssignedNumber>[
                      if (con.hasOrphanedCallerId)
                        AssignedNumber(
                          number: con.selectedCallerIdNumber.value,
                          description: 'Number Not Available - Please Reassign',
                        ),
                      if (hasAcctOption)
                        AssignedNumber(
                          number: acctNum,
                          description: 'Account default',
                        ),
                      ...con.assignedNumbers,
                    ];
                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: cs.outlineVariant),
                      itemBuilder: (_, i) {
                        final n = items[i];
                        final isOrphan = n.description ==
                            'Number Not Available - Please Reassign';
                        final isSelected =
                            n.number == con.selectedCallerIdNumber.value;
                        return ListTile(
                          leading: Icon(
                            isOrphan
                                ? Icons.warning_amber_rounded
                                : Icons.phone_outlined,
                            color: isOrphan
                                ? const Color(0xFFDC2626)
                                : cs.primary,
                          ),
                          title: Text(
                            n.label,
                            style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isOrphan
                                  ? const Color(0xFFDC2626)
                                  : cs.onSurface,
                            ),
                          ),
                          trailing: isSelected
                              ? Icon(Icons.check_rounded, color: cs.primary)
                              : null,
                          onTap: isOrphan
                              ? null
                              : () {
                                  Navigator.of(sheetCtx).pop();
                                  con.setCallerIdNumber(n.number);
                                },
                        );
                      },
                    );
                  }),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _orphanedCallerIdWarning() {
    return Container(
      padding: const EdgeInsets.all(V360Spacing.s3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        border: Border.all(color: const Color(0xFFFDE68A)),
        borderRadius: BorderRadius.circular(V360Radius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.warning_amber_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: V360Spacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Warning',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF92400E),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'The selected caller ID number is no longer available on this account. Please pick a different number.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFFB45309),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Recording prefs ─────────────────────────────────────────────────────
  Widget _recordingCard(BuildContext context, CallSettingsController con) {
    return V360Card(
      padding: const EdgeInsets.all(V360Spacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Obx(() => _SettingRow(
                iconBg: const Color(0xFFFFE4E6),
                iconColor: const Color(0xFFE11D48),
                icon: Icons.fiber_manual_record_rounded,
                title: 'Record internal calls',
                description:
                    'Save audio recordings of calls between extensions on your account.',
                value: con.callRecordingInternal.value,
                onChanged: con.toggleCallRecordingInternal,
              )),
          const SizedBox(height: V360Spacing.s3),
          Obx(() => _SettingRow(
                iconBg: const Color(0xFFDBEAFE),
                iconColor: const Color(0xFF2563EB),
                icon: Icons.fiber_manual_record_outlined,
                title: 'Record external calls',
                description:
                    'Save audio recordings of calls to and from numbers outside your account.',
                value: con.callRecordingExternal.value,
                onChanged: con.toggleCallRecordingExternal,
              )),
        ],
      ),
    );
  }

  // ── Misc ────────────────────────────────────────────────────────────────
  Widget _sectionLabel(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: V360Spacing.s2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text("You'll need to sign in again to make calls."),
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

// ── Shared row primitives (lifted from old call_settings_screen.dart) ─────

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: V360Spacing.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: V360Spacing.s3),
        Switch.adaptive(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _PillSettingRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PillSettingRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(V360Spacing.s3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(V360Radius.lg),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: _SettingRow(
        icon: icon,
        iconBg: iconBg,
        iconColor: iconColor,
        title: title,
        description: description,
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

class _IconHeader extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String description;

  const _IconHeader({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: V360Spacing.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VersionFooter extends StatefulWidget {
  const _VersionFooter();

  @override
  State<_VersionFooter> createState() => _VersionFooterState();
}

class _VersionFooterState extends State<_VersionFooter> {
  String? _label;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _label = 'Version ${info.version} (${info.buildNumber})');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Text(
        _label ?? '',
        style: TextStyle(
          fontSize: 12,
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
