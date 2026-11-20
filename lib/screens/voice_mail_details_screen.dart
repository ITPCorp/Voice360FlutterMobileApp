import 'package:itp_voice/services/notification_inbox.dart';
import 'package:itp_voice/routes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:itp_voice/controllers/base_screen_controller.dart';
import 'package:itp_voice/controllers/voicemails_controller.dart';
import 'package:itp_voice/design/v360.dart';
import 'package:itp_voice/models/get_voice_mails_response_model/result.dart';
import 'package:itp_voice/widgets/voicemail_player.dart';

class VoiceMailDetailsScreen extends StatefulWidget {
  const VoiceMailDetailsScreen({super.key});

  @override
  State<VoiceMailDetailsScreen> createState() =>
      _VoiceMailDetailsScreenState();
}

class _VoiceMailDetailsScreenState extends State<VoiceMailDetailsScreen> {
  final VoiceMailsController con = Get.find<VoiceMailsController>();
  final BaseScreenController base = Get.find<BaseScreenController>();
  late final VoiceMails vm;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    vm = (args is VoiceMails) ? args : con.voiceMail;
    NotificationInbox.voicemail(vm.msgId, vm.pk);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final number = vm.callerid?.trim() ?? '';
    final caller = number.isEmpty ? 'Caller ID unavailable' : number;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voicemail'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Download',
            onPressed: () => con.downloadVoicemail(vm.msgId),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: V360Colors.danger500),
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(V360Spacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: V360Spacing.s4),
            Center(child: V360Avatar(name: number, size: 88)),
            const SizedBox(height: V360Spacing.s4),
            Text(
              caller,
              style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: V360Spacing.s1),
            Text(
              _formatTime(vm.origtime),
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: V360Spacing.s6),
            V360Card(
              padding: const EdgeInsets.all(V360Spacing.s4),
              child:
                  VoiceMailPlayer(id: vm.msgId, durationSeconds: vm.duration),
            ),
            const SizedBox(height: V360Spacing.s5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (number.isNotEmpty)
                  _action(
                    icon: Icons.call_rounded,
                    label: 'Call back',
                    color: V360Colors.callAccept,
                    onTap: () => base.handleCall(caller, context),
                  ),
                if (number.isNotEmpty)
                  _action(
                    icon: Icons.chat_bubble_rounded,
                    label: 'Message',
                    color: cs.primary,
                    onTap: () => Get.toNamed(Routes.CHAT_SCREEN_ROUTE,
                        arguments: [null, number]),
                  ),
                _action(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete',
                  color: V360Colors.danger500,
                  onTap: _confirmDelete,
                ),
              ],
            ),
            const SizedBox(height: V360Spacing.s10),
          ],
        ),
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
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
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete voicemail?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: V360Colors.danger500),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final deleted = await con.deleteVoiceMail(vm.msgId);
    if (deleted && mounted && ModalRoute.of(context)?.isCurrent == true) {
      Navigator.pop(context);
    }
  }

  String _formatTime(int? epoch) {
    if (epoch == null) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(epoch * 1000).toLocal();
    final hh = t.hour > 12 ? t.hour - 12 : (t.hour == 0 ? 12 : t.hour);
    final mm = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour >= 12 ? 'PM' : 'AM';
    return '${t.month}/${t.day}/${t.year}  ·  $hh:$mm $ampm';
  }
}
