import 'package:flutter/material.dart';
import '../tokens.dart';

/// Bordered, rounded surface used to group content.
class V360Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? color;
  final bool elevated;
  final BorderRadius? borderRadius;

  const V360Card({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(V360Spacing.s4),
    this.margin,
    this.onTap,
    this.color,
    this.elevated = false,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = borderRadius ?? BorderRadius.circular(V360Radius.xl);
    final bg = color ?? cs.surface;
    final container = Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: Border.all(color: cs.outlineVariant),
        boxShadow: elevated ? V360Shadows.sm : null,
      ),
      padding: padding,
      child: child,
    );
    final wrapped = onTap == null
        ? container
        : Material(
            color: Colors.transparent,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              child: container,
            ),
          );
    return margin == null ? wrapped : Padding(padding: margin!, child: wrapped);
  }
}
