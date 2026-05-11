import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../tokens.dart';

/// 3x4 dialpad. Tap to emit the digit; long-press 0 emits "+".
class V360Dialpad extends StatelessWidget {
  final void Function(String digit) onKey;
  final double maxWidth;
  final bool compact;

  const V360Dialpad({
    super.key,
    required this.onKey,
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
                      onTap: () {
                        HapticFeedback.lightImpact();
                        onKey(k.digit);
                      },
                      onLongPress: k.digit == '0'
                          ? () {
                              HapticFeedback.mediumImpact();
                              onKey('+');
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
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool compact;

  const _DialKey({
    required this.digit,
    required this.letters,
    required this.onTap,
    this.onLongPress,
    this.compact = false,
  });

  @override
  State<_DialKey> createState() => _DialKeyState();
}

class _DialKeyState extends State<_DialKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = widget.compact ? 56.0 : 68.0;
    return AnimatedScale(
      scale: _pressed ? 0.9 : 1.0,
      duration: const Duration(milliseconds: 80),
      curve: Curves.easeOut,
      child: SizedBox(
        width: size,
        height: size,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: _pressed
                ? cs.primary.withOpacity(0.18)
                : cs.surfaceContainer,
            shape: BoxShape.circle,
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              onTapDown: (_) => setState(() => _pressed = true),
              onTapCancel: () => setState(() => _pressed = false),
              onTapUp: (_) => setState(() => _pressed = false),
              splashColor: cs.primary.withOpacity(0.22),
              highlightColor: Colors.transparent,
              customBorder: const CircleBorder(),
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
        ),
      ),
    );
  }
}
