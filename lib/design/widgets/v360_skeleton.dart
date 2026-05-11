import 'package:flutter/material.dart';
import '../tokens.dart';

/// Animated shimmer placeholder. Use V360Skeleton.line / .circle / .box.
class V360Skeleton extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  const V360Skeleton({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = const BorderRadius.all(Radius.circular(V360Radius.base)),
  });

  factory V360Skeleton.line({double? width, double height = 14}) =>
      V360Skeleton(width: width, height: height);

  factory V360Skeleton.circle({double size = 40}) => V360Skeleton(
        width: size,
        height: size,
        borderRadius: const BorderRadius.all(Radius.circular(V360Radius.full)),
      );

  factory V360Skeleton.box({
    double? width,
    double height = 80,
    double radius = V360Radius.lg,
  }) =>
      V360Skeleton(
        width: width,
        height: height,
        borderRadius: BorderRadius.all(Radius.circular(radius)),
      );

  @override
  State<V360Skeleton> createState() => _V360SkeletonState();
}

class _V360SkeletonState extends State<V360Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = cs.surfaceContainer;
    final highlight = cs.surfaceContainerHigh;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment(-1.0 - 2 * _ctrl.value, 0),
              end: Alignment(1.0 - 2 * _ctrl.value, 0),
              colors: [base, highlight, base],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}
