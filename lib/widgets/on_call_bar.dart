import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:itp_voice/screens/call_screen.dart';
import 'package:itp_voice/services/active_call_service.dart';
import 'package:itp_voice/services/app_wake/call_wake_service.dart';

/// Wraps every screen (GetMaterialApp.builder). While a call is active and the
/// in-call screen is not on top, shows "On call · <name> · mm:ss" above the
/// screen; tapping it returns to the call.
class OnCallBarHost extends StatelessWidget {
  final Widget child;
  const OnCallBarHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final svc = ActiveCallService.instance;
    if (defaultTargetPlatform != TargetPlatform.android) {
      return _callBar(context, svc);
    }
    // Keep the navigator mounted underneath the connecting screen while a
    // cold launch restores the session or navigates to the matched SIP call.
    return Stack(fit: StackFit.expand, children: [
      _callBar(context, svc),
      Obx(() {
        final wake = CallWakeService.instance;
        final c = wake.connectingCall.value;
        if (c == null) return const SizedBox.shrink();
        return BlockSemantics(
            child: ConnectingCallScreen(
          caller: c.callerLabel,
          hangup: () => wake.hangupConnecting(c),
        ));
      }),
    ]);
  }

  Widget _callBar(BuildContext context, ActiveCallService svc) {
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
              child: Container(
                constraints: BoxConstraints(minHeight: mq.padding.top + 48),
                padding: EdgeInsets.fromLTRB(16, mq.padding.top + 8, 16, 8),
                child: Row(
                  children: [
                    Icon(
                        svc.muted.value
                            ? Icons.mic_off_rounded
                            : Icons.call_rounded,
                        color: Colors.white,
                        size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(ringing ? 'View call' : 'Return to call',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(
                context: context, removeTop: true, child: child),
          ),
        ],
      );
    });
  }
}
