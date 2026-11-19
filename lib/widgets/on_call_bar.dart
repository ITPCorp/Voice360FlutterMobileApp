import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:itp_voice/services/active_call_service.dart';

/// Wraps every screen (GetMaterialApp.builder). While a call is active and the
/// in-call screen is not on top, shows "On call · <name> · mm:ss" above the
/// screen; tapping it returns to the call.
class OnCallBarHost extends StatelessWidget {
  final Widget child;
  const OnCallBarHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final svc = ActiveCallService.instance;
    return Obx(() {
      if (!svc.barVisible) return child;
      final mq = MediaQuery.of(context);
      final ringing = svc.isIncomingRinging;
      final connected = svc.isConnected;
      final label = ringing
          ? 'Incoming call · ${svc.peerName.value}'
          : connected
              ? 'On call · ${svc.peerName.value}${svc.elapsed.value.isEmpty ? '' : ' · ${svc.elapsed.value}'}'
              : 'Calling ${svc.peerName.value}…';
      return Column(
        children: [
          Material(
            color: ringing ? const Color(0xFF1D4ED8) : const Color(0xFF15803D),
            child: InkWell(
              onTap: svc.openCallScreen,
              child: Padding(
                padding: EdgeInsets.only(
                    top: mq.padding.top + 6, bottom: 8, left: 16, right: 16),
                child: Row(
                  children: [
                    Icon(svc.muted.value ? Icons.mic_off_rounded : Icons.call_rounded,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(ringing ? 'Tap to answer' : 'Tap to return',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(context: context, removeTop: true, child: child),
          ),
        ],
      );
    });
  }
}
