import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:itp_voice/controllers/base_screen_controller.dart';
import 'package:itp_voice/controllers/voicemails_controller.dart';
import 'package:itp_voice/design/v360.dart';
import 'package:itp_voice/models/get_voice_mails_response_model/result.dart';
import 'package:itp_voice/routes.dart';

class VoiceMailScreen extends StatefulWidget {
  const VoiceMailScreen({super.key});

  @override
  State<VoiceMailScreen> createState() => _VoiceMailScreenState();
}

class _VoiceMailScreenState extends State<VoiceMailScreen> {
  final VoiceMailsController con = Get.put(VoiceMailsController());
  final BaseScreenController base = Get.find<BaseScreenController>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voicemail')),
      body: GetBuilder<VoiceMailsController>(
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
                  hintText: 'Search voicemails',
                  onChanged: (_) => con.update(),
                  onClear: () {
                    con.searchController.clear();
                    con.update();
                  },
                ),
              ),
              Expanded(
                child: con.isVoiceMailsLoading && con.voiceMails.isEmpty
                    ? const _VoicemailLoading()
                    : _buildList(context),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final List<VoiceMails> data =
        (con.getDataList() ?? const <VoiceMails>[]) as List<VoiceMails>;
    if (data.isEmpty) {
      return const V360EmptyState(
        icon: Icons.voicemail_outlined,
        title: 'No voicemails',
        message: 'Missed calls with messages will appear here.',
      );
    }
    return RefreshIndicator(
      onRefresh: () async => con.fetchVoiceMails(),
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: V360Spacing.s10),
        itemCount: data.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
          indent: 76,
        ),
        itemBuilder: (_, i) => _row(data[i], i),
      ),
    );
  }

  Widget _row(VoiceMails v, int index) {
    final caller = (v.callerid ?? '').isNotEmpty ? v.callerid! : 'Unknown';
    final time = _formatTime(v.origtime);
    final dur = _formatDuration(v.duration);
    return V360ListTile(
      leading: V360Avatar(name: caller, size: 48),
      title: caller,
      subtitle: '$time${dur.isNotEmpty ? '  ·  $dur' : ''}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.call_rounded, color: V360Colors.callAccept),
            onPressed: () => base.handleCall(caller, context),
          ),
          IconButton(
            icon: Icon(
              Icons.play_circle_fill_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 32,
            ),
            onPressed: () {
              con.tappedIndex = index;
              con.voiceMail = v;
              Get.toNamed(Routes.VOICE_MAIL_DETAILS_ROUTE, arguments: v);
            },
          ),
        ],
      ),
      onTap: () {
        con.tappedIndex = index;
        con.voiceMail = v;
        Get.toNamed(Routes.VOICE_MAIL_DETAILS_ROUTE, arguments: v);
      },
    );
  }

  String _formatTime(int? epoch) {
    if (epoch == null) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(epoch * 1000).toLocal();
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      final hh = t.hour > 12 ? t.hour - 12 : (t.hour == 0 ? 12 : t.hour);
      final mm = t.minute.toString().padLeft(2, '0');
      final ampm = t.hour >= 12 ? 'PM' : 'AM';
      return '$hh:$mm $ampm';
    }
    return '${t.month}/${t.day}/${t.year % 100}';
  }

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return '';
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _VoicemailLoading extends StatelessWidget {
  const _VoicemailLoading();
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 6,
      padding: const EdgeInsets.symmetric(horizontal: V360Spacing.s4),
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(vertical: V360Spacing.s3),
        child: Row(
          children: [
            V360Skeleton.circle(size: 48),
            const SizedBox(width: V360Spacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  V360Skeleton.line(width: 140, height: 14),
                  const SizedBox(height: 6),
                  V360Skeleton.line(width: 80, height: 12),
                ],
              ),
            ),
            V360Skeleton.circle(size: 36),
          ],
        ),
      ),
    );
  }
}
