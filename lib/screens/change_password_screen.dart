import 'package:flutter/material.dart';
import 'package:itp_voice/design/v360.dart';
import 'package:itp_voice/helpers/config.dart';
import 'package:url_launcher/url_launcher.dart';

class ChangePassordScreen extends StatelessWidget {
  const ChangePassordScreen({super.key});

  Future<void> _openReset(BuildContext context) async {
    try {
      if (await launchUrl(Config.webAppUri('/reset-pw'),
          mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {
      // Some devices have no browser installed.
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open your browser.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(V360Spacing.s4),
          children: [
            const Text(
                'Open Voice360 in your browser to request a password reset email.'),
            const SizedBox(height: V360Spacing.s6),
            V360Button(
              label: 'Open password reset',
              leadingIcon: Icons.open_in_new_rounded,
              onPressed: () => _openReset(context),
            ),
          ],
        ),
      ),
    );
  }
}
