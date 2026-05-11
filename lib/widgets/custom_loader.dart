import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:itp_voice/design/v360.dart';

/// Full-screen modal loader. Backdrop is blurred + dimmed, content is a
/// floating glass card with a sky-blue spinner.
///
/// Drop-in replacement for the legacy implementation — same static API.
class CustomLoader {
  static bool _open = false;

  static void showLoader({String? message}) {
    if (_open) return;
    _open = true;
    Get.dialog(
      _V360Loader(message: message),
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.35),
    ).whenComplete(() => _open = false);
  }

  static void dismisLoader() {
    if (!_open) return;
    if (Get.isDialogOpen ?? false) {
      Get.back();
    }
  }
}

class _V360Loader extends StatelessWidget {
  final String? message;
  const _V360Loader({this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return WillPopScope(
      onWillPop: () async => false,
      child: Material(
        type: MaterialType.transparency,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: V360Spacing.s6,
                vertical: V360Spacing.s6,
              ),
              constraints: const BoxConstraints(minWidth: 132, minHeight: 132),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(V360Radius.xxl),
                boxShadow: V360Shadows.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation(cs.primary),
                    ),
                  ),
                  if (message != null && message!.isNotEmpty) ...[
                    const SizedBox(height: V360Spacing.s4),
                    Text(
                      message!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
