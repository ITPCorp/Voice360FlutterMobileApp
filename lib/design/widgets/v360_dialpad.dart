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

class _DialKey extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = compact ? 56.0 : 68.0;
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: cs.surfaceContainer,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          customBorder: const CircleBorder(),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  digit,
                  style: TextStyle(
                    fontSize: compact ? 24 : 28,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                    height: 1,
                  ),
                ),
                if (letters.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      letters,
                      style: TextStyle(
                        fontSize: compact ? 8 : 10,
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
    );
  }
}
