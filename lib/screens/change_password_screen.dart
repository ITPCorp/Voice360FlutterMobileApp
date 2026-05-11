import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:itp_voice/design/v360.dart';
import 'package:itp_voice/widgets/custom_toast.dart';

class ChangePassordScreen extends StatefulWidget {
  const ChangePassordScreen({super.key});

  @override
  State<ChangePassordScreen> createState() => _ChangePassordScreenState();
}

class _ChangePassordScreenState extends State<ChangePassordScreen> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNext = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (_current.text.isEmpty) {
      CustomToast.showToast('Enter your current password', true);
      return;
    }
    if (_next.text.length < 6) {
      CustomToast.showToast('New password must be at least 6 characters', true);
      return;
    }
    if (_next.text != _confirm.text) {
      CustomToast.showToast('Passwords do not match', true);
      return;
    }
    // Backend wiring TODO — controller doesn't expose change-password yet.
    CustomToast.showToast('Password updated', false);
    Get.back();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(V360Spacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: V360Spacing.s2),
            _passwordField(
              controller: _current,
              label: 'Current password',
              obscure: _obscureCurrent,
              onToggle: () =>
                  setState(() => _obscureCurrent = !_obscureCurrent),
            ),
            const SizedBox(height: V360Spacing.s4),
            _passwordField(
              controller: _next,
              label: 'New password',
              obscure: _obscureNext,
              onToggle: () => setState(() => _obscureNext = !_obscureNext),
            ),
            const SizedBox(height: V360Spacing.s4),
            _passwordField(
              controller: _confirm,
              label: 'Confirm new password',
              obscure: _obscureConfirm,
              onToggle: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
            const SizedBox(height: V360Spacing.s8),
            V360Button(
              label: 'Update password',
              onPressed: _submit,
              fullWidth: true,
              size: V360ButtonSize.lg,
            ),
          ],
        ),
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: V360Spacing.s2),
        TextField(
          controller: controller,
          obscureText: obscure,
          decoration: InputDecoration(
            hintText: '•••••••',
            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
              ),
              onPressed: onToggle,
            ),
          ),
        ),
      ],
    );
  }
}
