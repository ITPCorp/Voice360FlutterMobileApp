import 'package:flutter/material.dart';

/// Round "people" badge used in place of [V360Avatar] for group threads,
/// the mobile twin of the web's faUsers avatar.
class V360GroupAvatar extends StatelessWidget {
  final double size;

  const V360GroupAvatar({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.group_rounded,
        size: size * 0.5,
        color: cs.onPrimaryContainer,
      ),
    );
  }
}
