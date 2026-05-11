import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:itp_voice/design/v360.dart';

/// Modern toast / inline notification.
///
/// Drop-in replacement for the legacy implementation — same `showToast(body,
/// error)` signature. Renders a Material 3 SnackBar with an icon, brand
/// colors, and a tap-to-dismiss action.
class CustomToast {
  static void showToast(String body, bool error) {
    final ctx = Get.context;
    if (ctx == null) return;

    final cs = Theme.of(ctx).colorScheme;

    final color = error ? V360Colors.danger600 : V360Colors.success600;
    final icon = error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded;
    final title = error ? 'Error' : 'Success';

    ScaffoldMessenger.of(ctx)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: cs.inverseSurface,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(
            V360Spacing.s4,
            V360Spacing.s4,
            V360Spacing.s4,
            V360Spacing.s4,
          ),
          duration: Duration(seconds: error ? 4 : 2),
          elevation: 6,
          padding: const EdgeInsets.symmetric(
            horizontal: V360Spacing.s4,
            vertical: V360Spacing.s3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(V360Radius.lg),
          ),
          content: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: V360Spacing.s3),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: cs.onInverseSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: TextStyle(
                        color: cs.onInverseSurface.withOpacity(0.85),
                        fontSize: 13,
                        height: 1.3,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }
}
