import 'package:flutter/material.dart';
import '../tokens.dart';

enum V360ButtonVariant { primary, secondary, outline, ghost, danger }

enum V360ButtonSize { sm, md, lg }

class V360Button extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final V360ButtonVariant variant;
  final V360ButtonSize size;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final bool loading;
  final bool fullWidth;

  const V360Button({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = V360ButtonVariant.primary,
    this.size = V360ButtonSize.md,
    this.leadingIcon,
    this.trailingIcon,
    this.loading = false,
    this.fullWidth = false,
  });

  double get _height => switch (size) {
        V360ButtonSize.sm => 36,
        V360ButtonSize.md => 48,
        V360ButtonSize.lg => 56,
      };

  double get _fontSize => switch (size) {
        V360ButtonSize.sm => 13,
        V360ButtonSize.md => 14,
        V360ButtonSize.lg => 16,
      };

  EdgeInsets get _padding => switch (size) {
        V360ButtonSize.sm => const EdgeInsets.symmetric(horizontal: V360Spacing.s4),
        V360ButtonSize.md => const EdgeInsets.symmetric(horizontal: V360Spacing.s5),
        V360ButtonSize.lg => const EdgeInsets.symmetric(horizontal: V360Spacing.s6),
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final disabled = onPressed == null || loading;
    late Color background;
    late Color foreground;
    late Color? border;
    switch (variant) {
      case V360ButtonVariant.primary:
        background = cs.primary;
        foreground = cs.onPrimary;
        border = null;
        break;
      case V360ButtonVariant.secondary:
        background = cs.surfaceContainer;
        foreground = cs.onSurface;
        border = null;
        break;
      case V360ButtonVariant.outline:
        background = Colors.transparent;
        foreground = cs.onSurface;
        border = cs.outline;
        break;
      case V360ButtonVariant.ghost:
        background = Colors.transparent;
        foreground = cs.primary;
        border = null;
        break;
      case V360ButtonVariant.danger:
        background = cs.error;
        foreground = cs.onError;
        border = null;
        break;
    }
    if (disabled) {
      background = background.withOpacity(background.opacity * 0.6);
      foreground = foreground.withOpacity(foreground.opacity * 0.6);
    }

    final child = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: _fontSize + 4,
            height: _fontSize + 4,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(foreground),
            ),
          )
        else if (leadingIcon != null) ...[
          Icon(leadingIcon, size: _fontSize + 4, color: foreground),
          const SizedBox(width: V360Spacing.s2),
        ],
        if (!loading)
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: _fontSize,
                fontWeight: FontWeight.w600,
                color: foreground,
                letterSpacing: 0.1,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (!loading && trailingIcon != null) ...[
          const SizedBox(width: V360Spacing.s2),
          Icon(trailingIcon, size: _fontSize + 4, color: foreground),
        ],
      ],
    );

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: _height,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(V360Radius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: disabled ? null : onPressed,
          splashColor: foreground.withOpacity(0.08),
          highlightColor: foreground.withOpacity(0.04),
          child: Container(
            padding: _padding,
            decoration: border != null
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(V360Radius.lg),
                    border: Border.all(color: border, width: 1),
                  )
                : null,
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}
