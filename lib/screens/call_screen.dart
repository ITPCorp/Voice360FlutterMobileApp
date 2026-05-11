import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:itp_voice/controllers/call_screen_controller.dart';
import 'package:itp_voice/design/v360.dart';
import 'package:sip_ua/sip_ua.dart';

class CallScreen extends StatelessWidget {
  CallScreen({super.key});
  final CallScreenController con = Get.put(CallScreenController());

  String _peerName() {
    final id = con.call?.remote_identity ?? '';
    if (id.isEmpty) return 'Unknown';
    final m = RegExp(r'"([^"]+)"').firstMatch(id);
    if (m != null) return m.group(1)!;
    final m2 = RegExp(r'sip:([^@]+)').firstMatch(id);
    if (m2 != null) return m2.group(1)!;
    return id;
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
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
            child: Obx(() => _buildContent(context)),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final peer = _peerName();
    final incoming = con.isIncomingCall?.value == true &&
        con.isIncomingCallAccepted?.value == false;

    return Column(
      children: [
        const SizedBox(height: V360Spacing.s5),
        // Status pill
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: V360Spacing.s3,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(V360Radius.full),
            border:
                Border.all(color: Colors.white.withOpacity(0.16)),
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
        const SizedBox(height: V360Spacing.s10),

        // Avatar + name
        V360Avatar(name: peer, size: 128),
        const SizedBox(height: V360Spacing.s5),
        Text(
          peer,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: V360Spacing.s2),
        Text(
          con.timeLabel.value.isEmpty ? '—' : con.timeLabel.value,
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
          _CallDialpad(onKey: (d) => con.handleDtmf(d), onClose: () => con.showNumpad.value = false),

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
    if (incoming) return 'INCOMING';
    final s = con.state.value;
    if (s == CallStateEnum.CALL_INITIATION) return 'CALLING';
    if (s == CallStateEnum.CONNECTING) return 'CONNECTING';
    if (s == CallStateEnum.PROGRESS) return 'RINGING';
    if (s == CallStateEnum.ACCEPTED || s == CallStateEnum.CONFIRMED) {
      return con.hold.value ? 'ON HOLD' : 'IN CALL';
    }
    if (s == CallStateEnum.ENDED) return 'CALL ENDED';
    if (s == CallStateEnum.FAILED) return 'CALL FAILED';
    return 'CALL';
  }

  Widget _incomingControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundIconButton(
          icon: Icons.call_end_rounded,
          color: V360Colors.callDecline,
          size: 72,
          onTap: () => con.handleHangup(goBack: true),
        ),
        _RoundIconButton(
          icon: Icons.call_rounded,
          color: V360Colors.callAccept,
          size: 72,
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
            _ToggleButton(
              icon: con.audioMuted.value
                  ? Icons.mic_off_rounded
                  : Icons.mic_rounded,
              label: con.audioMuted.value ? 'Unmute' : 'Mute',
              active: con.audioMuted.value,
              onTap: con.muteAudio,
            ),
            _ToggleButton(
              icon: Icons.dialpad_rounded,
              label: 'Keypad',
              active: con.showNumpad.value,
              onTap: () => con.showNumpad.value = !con.showNumpad.value,
            ),
            _ToggleButton(
              icon: con.speakerOn.value
                  ? Icons.volume_up_rounded
                  : Icons.volume_down_rounded,
              label: 'Speaker',
              active: con.speakerOn.value,
              onTap: con.toggleSpeaker,
            ),
          ],
        ),
        const SizedBox(height: V360Spacing.s5),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _ToggleButton(
              icon: Icons.pause_rounded,
              label: con.hold.value ? 'Resume' : 'Hold',
              active: con.hold.value,
              onTap: con.handleHold,
            ),
            _ToggleButton(
              icon: Icons.fiber_manual_record_rounded,
              label: 'Record',
              active: false,
              onTap: () {},
              disabled: true,
            ),
            _ToggleButton(
              icon: Icons.add_rounded,
              label: 'Add call',
              active: false,
              onTap: () {},
              disabled: true,
            ),
          ],
        ),
        const SizedBox(height: V360Spacing.s8),
        _RoundIconButton(
          icon: Icons.call_end_rounded,
          color: V360Colors.callDecline,
          size: 72,
          onTap: () => con.handleHangup(goBack: true),
        ),
      ],
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
    return Column(
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
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  splashColor: widget.active
                      ? Colors.black.withOpacity(0.08)
                      : Colors.white.withOpacity(0.18),
                  highlightColor: Colors.transparent,
                  onTapDown: widget.disabled
                      ? null
                      : (_) => setState(() => _pressed = true),
                  onTapCancel: widget.disabled
                      ? null
                      : () => setState(() => _pressed = false),
                  onTapUp: widget.disabled
                      ? null
                      : (_) => setState(() => _pressed = false),
                  onTap: widget.disabled
                      ? null
                      : () {
                          HapticFeedback.lightImpact();
                          widget.onTap();
                        },
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
          ),
        ),
        const SizedBox(height: V360Spacing.s2),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          style: TextStyle(
            color: widget.disabled
                ? Colors.white.withOpacity(0.4)
                : Colors.white.withOpacity(0.85),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
          child: Text(widget.label),
        ),
      ],
    );
  }
}

class _RoundIconButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onTap;
  const _RoundIconButton({
    required this.icon,
    required this.color,
    required this.size,
    required this.onTap,
  });

  @override
  State<_RoundIconButton> createState() => _RoundIconButtonState();
}

class _RoundIconButtonState extends State<_RoundIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
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
          child: InkWell(
            customBorder: const CircleBorder(),
            splashColor: Colors.white.withOpacity(0.18),
            highlightColor: Colors.transparent,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapCancel: () => setState(() => _pressed = false),
            onTapUp: (_) => setState(() => _pressed = false),
            onTap: () {
              HapticFeedback.mediumImpact();
              widget.onTap();
            },
            child: Icon(widget.icon, color: Colors.white, size: widget.size * 0.45),
          ),
        ),
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
