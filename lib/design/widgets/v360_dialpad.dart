import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../tokens.dart';

/// 3x4 dialpad.
///
/// Keys fire on finger DOWN through a raw [Listener]: they never enter the
/// gesture arena, so the Dial tab's horizontal swipe (TabBarView) or a slight
/// finger slide cannot swallow a digit, and fast typing with two thumbs counts
/// every touch. The old InkWell fired on finger UP and only if it won the
/// arena, which dropped digits when typing at normal speed.
///
/// Long-press 0: the 0 is entered on touch; holding it turns it into "+"
/// through [onPlus] (replace the 0 that was just entered).
class V360Dialpad extends StatelessWidget {
  final void Function(String digit) onKey;
  final VoidCallback? onPlus;
  final double maxWidth;
  final bool compact;

  const V360Dialpad({
    super.key,
    required this.onKey,
    this.onPlus,
    this.maxWidth = 360,
    this.compact = false,
  });

  static const List<List<_Key>> _keys = [
    [_Key('1', ''), _Key('2', 'ABC'), _Key('3', 'DEF')],
    [_Key('4', 'GHI'), _Key('5', 'JKL'), _Key('6', 'MNO')],
    [_Key('7', 'PQRS'), _Key('8', 'TUV'), _Key('9', 'WXYZ')],
    [_Key('*', ''), _Key('0', '+'), _Key('#', '')],
  ];

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in _keys)
            Padding(
              padding: EdgeInsets.symmetric(
                vertical: compact ? V360Spacing.s1 : V360Spacing.s2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final k in row)
                    _DialKey(
                      digit: k.digit,
                      letters: k.letters,
                      compact: compact,
                      onDown: () {
                        HapticFeedback.lightImpact();
                        onKey(k.digit);
                      },
                      onHold: k.digit == '0' && onPlus != null
                          ? () {
                              HapticFeedback.mediumImpact();
                              onPlus!();
                            }
                          : null,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Key {
  final String digit;
  final String letters;
  const _Key(this.digit, this.letters);
}

class _DialKey extends StatefulWidget {
  final String digit;
  final String letters;
  final VoidCallback onDown;
  final VoidCallback? onHold;
  final bool compact;

  const _DialKey({
    required this.digit,
    required this.letters,
    required this.onDown,
    this.onHold,
    this.compact = false,
  });

  @override
  State<_DialKey> createState() => _DialKeyState();
}

class _DialKeyState extends State<_DialKey> {
  static const _holdTime = Duration(milliseconds: 550);
  final Set<int> _pointers = {};
  Timer? _hold;

  bool get _pressed => _pointers.isNotEmpty;

  void _down(PointerDownEvent e) {
    _pointers.add(e.pointer);
    widget.onDown();
    if (widget.onHold != null) {
      _hold?.cancel();
      _hold = Timer(_holdTime, () {
        if (_pointers.isNotEmpty) widget.onHold!();
      });
    }
    setState(() {});
  }

  void _up(int pointer) {
    _pointers.remove(pointer);
    if (_pointers.isEmpty) _hold?.cancel();
    setState(() {});
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = widget.compact ? 56.0 : 68.0;
    return Semantics(
        button: true,
        label: [widget.digit, if (widget.letters.isNotEmpty) widget.letters]
            .join(', '),
        onTap: widget.onDown,
        onLongPress: widget.onHold == null
          ? null
          : () {
              widget.onDown();
              widget.onHold!();
            },
        excludeSemantics: true,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _down,
          onPointerUp: (e) => _up(e.pointer),
          onPointerCancel: (e) => _up(e.pointer),
          child: AnimatedScale(
            scale: _pressed ? 0.9 : 1.0,
            duration: const Duration(milliseconds: 60),
            curve: Curves.easeOut,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: _pressed
                    ? cs.primary.withOpacity(0.18)
                    : cs.surfaceContainer,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.digit,
                      style: TextStyle(
                        fontSize: widget.compact ? 24 : 28,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurface,
                        height: 1,
                      ),
                    ),
                    if (widget.letters.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          widget.letters,
                          style: TextStyle(
                            fontSize: widget.compact ? 8 : 10,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                            letterSpacing: 1.6,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ));
  }
}
