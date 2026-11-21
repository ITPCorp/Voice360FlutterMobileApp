import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:itp_voice/controllers/call_screen_controller.dart';
import 'package:itp_voice/design/v360.dart';
import 'package:itp_voice/services/app_wake/call_wake_service.dart';
import 'package:sip_ua/sip_ua.dart';

class CallScreen extends StatelessWidget {
  CallScreen({super.key});
  final CallScreenController con = _controllerFor(Get.arguments);

  /// One controller per call: a leftover controller from an earlier call
  /// (or an earlier visit) must not show the wrong call.
  static CallScreenController _controllerFor(dynamic arg) {
    if (Get.isRegistered<CallScreenController>()) {
      final existing = Get.find<CallScreenController>();
      if (arg is! Call || existing.call?.id == arg.id) return existing;
      Get.delete<CallScreenController>(force: true);
    }
    return Get.put(CallScreenController());
  }

  String _peerName() {
    final wake = CallWakeService.instance.androidWakeFor(con.call?.id);
    if (wake != null) return wake.callerLabel;
    final id = con.call?.remote_identity ?? '';
    if (id.isEmpty) return 'Caller ID unavailable';
    final m = RegExp(r'"([^"]+)"').firstMatch(id);
    if (m != null) return m.group(1)!;
    final m2 = RegExp(r'sip:([^@]+)').firstMatch(id);
    if (m2 != null) return m2.group(1)!;
    return id;
  }

  @override
  Widget build(BuildContext context) {
    return _CallSurface(content: Obx(() => _buildContent(context)));
  }

  Widget _buildContent(BuildContext context) {
    final peer = _peerName();
    final incoming = con.isIncomingCall?.value == true &&
        con.isIncomingCallAccepted?.value == false;

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            if (Navigator.of(context).canPop())
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'Minimize call',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: Colors.white),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: V360Spacing.s3,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(V360Radius.full),
                border: Border.all(color: Colors.white.withOpacity(0.16)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: V360Colors.success500,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _statusText(incoming),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: V360Spacing.s6),

        // Avatar + name
        if (!con.showNumpad.value) V360Avatar(name: peer, size: 96),
        const SizedBox(height: V360Spacing.s5),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              peer,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
              textAlign: TextAlign.center,
            )),
        const SizedBox(height: V360Spacing.s2),
        if (con.timeLabel.value.isNotEmpty)
          Text(
            con.timeLabel.value,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 16,
              fontWeight: FontWeight.w500,
              letterSpacing: 1,
            ),
          ),

        const Spacer(),

        // Dialpad overlay
        if (con.showNumpad.value)
          _CallDialpad(
              onKey: (d) => con.handleDtmf(d),
              onClose: () => con.showNumpad.value = false),

        // Action buttons
        if (!con.showNumpad.value)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: V360Spacing.s8),
            child: incoming ? _incomingControls() : _activeControls(),
          ),
        const SizedBox(height: V360Spacing.s8),
      ],
    );
  }

  String _statusText(bool incoming) {
    if (incoming) return 'Incoming';
    final s = con.state.value;
    if (s == CallStateEnum.CALL_INITIATION) return 'Calling';
    if (s == CallStateEnum.CONNECTING) return 'Connecting';
    if (s == CallStateEnum.PROGRESS) return 'Ringing';
    if (s == CallStateEnum.ACCEPTED || s == CallStateEnum.CONFIRMED) {
      return con.hold.value ? 'On hold' : 'In call';
    }
    if (s == CallStateEnum.ENDED) return 'Call ended';
    if (s == CallStateEnum.FAILED) return 'Call failed';
    return 'Call';
  }

  static IconData _routeIcon(String r) => switch (r) {
        'speaker' => Icons.volume_up_rounded,
        'bluetooth' => Icons.bluetooth_audio_rounded,
        'wired' => Icons.headset_rounded,
        _ => Icons.volume_down_rounded,
      };

  String _routeLabel(String r) => switch (r) {
        'speaker' => 'Speaker',
        'bluetooth' => con.active.bluetoothName.value?.isNotEmpty == true
            ? con.active.bluetoothName.value!
            : 'Bluetooth',
        'wired' => 'Headset',
        _ => 'Phone',
      };

  /// Speaker button: a plain toggle with only earpiece + speaker; with a
  /// headset connected, pick the output (Phone / Speaker / Bluetooth / Headset).
  void _onAudioTap() {
    final a = con.active;
    if (!a.hasRouteChoice) {
      a.toggleSpeaker();
      return;
    }
    Get.bottomSheet(
      SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final r in a.routes)
              ListTile(
                leading: Icon(_routeIcon(r)),
                title: Text(_routeLabel(r)),
                trailing:
                    a.route.value == r ? const Icon(Icons.check_rounded) : null,
                onTap: () {
                  Get.back();
                  a.setRoute(r);
                },
              ),
          ],
        ),
      ),
      backgroundColor: Theme.of(Get.context!).colorScheme.surface,
    );
  }

  Widget _incomingControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundIconButton(
          icon: Icons.call_end_rounded,
          color: V360Colors.callDecline,
          size: 72,
          label: 'Decline',
          onTap: () => con.handleHangup(goBack: true),
        ),
        _RoundIconButton(
          icon: Icons.call_rounded,
          color: V360Colors.callAccept,
          size: 72,
          label: 'Answer',
          onTap: con.handleAccept,
        ),
      ],
    );
  }

  Widget _activeControls() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Expanded(
                child: _ToggleButton(
              icon: con.audioMuted.value
                  ? Icons.mic_off_rounded
                  : Icons.mic_rounded,
              label: con.audioMuted.value ? 'Unmute' : 'Mute',
              active: con.audioMuted.value,
              onTap: con.muteAudio,
            )),
            Expanded(
                child: _ToggleButton(
              icon: Icons.dialpad_rounded,
              label: 'Keypad',
              active: con.showNumpad.value,
              onTap: () => con.showNumpad.value = !con.showNumpad.value,
            )),
            Expanded(
                child: _ToggleButton(
              icon: _routeIcon(con.active.route.value),
              label: con.active.hasRouteChoice
                  ? _routeLabel(con.active.route.value)
                  : 'Speaker',
              active: con.active.route.value == 'speaker',
              onTap: _onAudioTap,
            )),
          ],
        ),
        const SizedBox(height: V360Spacing.s5),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Expanded(
                child: _ToggleButton(
              icon: Icons.pause_rounded,
              label: con.hold.value ? 'Resume' : 'Hold',
              active: con.hold.value,
              onTap: con.handleHold,
            )),
            Expanded(
                child: _ToggleButton(
              icon: Icons.fiber_manual_record_rounded,
              label: 'Record',
              active: false,
              onTap: () {},
              disabled: true,
            )),
            Expanded(
                child: _ToggleButton(
              icon: Icons.add_rounded,
              label: 'Add call',
              active: false,
              onTap: () {},
              disabled: true,
            )),
          ],
        ),
        const SizedBox(height: V360Spacing.s8),
        _RoundIconButton(
          icon: Icons.call_end_rounded,
          color: V360Colors.callDecline,
          size: 72,
          label: 'End call',
          onTap: () => con.handleHangup(goBack: true),
        ),
      ],
    );
  }
}

/// The wake push identifies the caller even before Flutter has a SIP session.
class ConnectingCallScreen extends StatelessWidget {
  const ConnectingCallScreen(
      {super.key, required this.caller, required this.hangup});
  final String caller;
  final VoidCallback hangup;

  @override
  Widget build(BuildContext context) => _CallSurface(
          content: Column(children: [
        const SizedBox(height: V360Spacing.s6),
        Semantics(
            liveRegion: true,
            child: const Text('Connecting…',
                style: TextStyle(color: Colors.white, fontSize: 16))),
        const SizedBox(height: V360Spacing.s6),
        V360Avatar(name: caller, size: 96),
        const SizedBox(height: V360Spacing.s5),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(caller,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700))),
        const Spacer(),
        _RoundIconButton(
            icon: Icons.call_end_rounded,
            color: V360Colors.callDecline,
            size: 72,
            label: 'End call',
            onTap: hangup),
        const SizedBox(height: V360Spacing.s8),
      ]));
}

class _CallSurface extends StatelessWidget {
  const _CallSurface({required this.content});
  final Widget content;
  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      // Android Back leaves this screen and keeps the call: the "On call" bar
      // on every screen and the ongoing-call notification lead back here.
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0F172A),
                Color(0xFF0C4A6E),
                Color(0xFF075985),
              ],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(child: content),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool disabled;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.disabled = false,
  });

  @override
  State<_ToggleButton> createState() => _ToggleButtonState();
}

class _ToggleButtonState extends State<_ToggleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final fg = widget.disabled
        ? Colors.white.withOpacity(0.3)
        : (widget.active ? const Color(0xFF0F172A) : Colors.white);
    final bg = widget.active
        ? Colors.white
        : Colors.white.withOpacity(widget.disabled ? 0.06 : 0.14);
    return Semantics(
      button: true,
      enabled: !widget.disabled,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onHighlightChanged: (pressed) => setState(() => _pressed = pressed),
        onTap: widget.disabled
            ? null
            : () {
                HapticFeedback.lightImpact();
                widget.onTap();
              },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: _pressed ? 0.88 : 1.0,
              duration: const Duration(milliseconds: 90),
              curve: Curves.easeOut,
              child: SizedBox(
                width: 64,
                height: 64,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    color: bg,
                    shape: BoxShape.circle,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 140),
                    transitionBuilder: (child, anim) => ScaleTransition(
                      scale: anim,
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                    child: Icon(
                      widget.icon,
                      key: ValueKey(widget.icon),
                      color: fg,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: V360Spacing.s2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: TextStyle(
                color: widget.disabled
                    ? Colors.white.withOpacity(0.4)
                    : Colors.white.withOpacity(0.85),
                fontFamily: 'Noto Sans',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
              child: Text(widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;
  final String label;
  final VoidCallback onTap;
  const _RoundIconButton({
    required this.icon,
    required this.color,
    required this.size,
    required this.label,
    required this.onTap,
  });

  @override
  State<_RoundIconButton> createState() => _RoundIconButtonState();
}

class _RoundIconButtonState extends State<_RoundIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onHighlightChanged: (pressed) => setState(() => _pressed = pressed),
        onTap: () {
          HapticFeedback.mediumImpact();
          widget.onTap();
        },
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedScale(
            scale: _pressed ? 0.9 : 1.0,
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: Material(
                color: widget.color,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                elevation: _pressed ? 2 : 8,
                shadowColor: widget.color.withOpacity(0.5),
                animationDuration: const Duration(milliseconds: 120),
                child: Icon(widget.icon,
                    color: Colors.white, size: widget.size * 0.45),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(widget.label,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
        ]),
      ),
    );
  }
}

class _CallDialpad extends StatelessWidget {
  final void Function(String) onKey;
  final VoidCallback onClose;
  const _CallDialpad({required this.onKey, required this.onClose});

  @override
  Widget build(BuildContext context) {
    // Force dark colour scheme so the dialpad keys look right on the
    // gradient background regardless of the user's system theme.
    final cs = Theme.of(context).colorScheme.copyWith(
          surfaceContainer: Colors.white.withOpacity(0.14),
          onSurface: Colors.white,
          onSurfaceVariant: Colors.white.withOpacity(0.7),
        );
    return Theme(
      data: Theme.of(context).copyWith(colorScheme: cs),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: V360Spacing.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            V360Dialpad(onKey: onKey, compact: true),
            const SizedBox(height: V360Spacing.s4),
            GestureDetector(
              onTap: onClose,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
