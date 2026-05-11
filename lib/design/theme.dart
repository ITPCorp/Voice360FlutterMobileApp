import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tokens.dart';

/// Application of Voice360 design tokens to a Flutter ThemeData.
class V360Theme {
  V360Theme._();

  static const String _fontFamily = 'Noto Sans';

  static ThemeData light() {
    final ColorScheme scheme = const ColorScheme(
      brightness: Brightness.light,
      primary: V360Colors.primary500,
      onPrimary: V360Colors.neutral0,
      primaryContainer: V360Colors.primary100,
      onPrimaryContainer: V360Colors.primary900,
      secondary: V360Colors.neutral800,
      onSecondary: V360Colors.neutral0,
      secondaryContainer: V360Colors.neutral100,
      onSecondaryContainer: V360Colors.neutral900,
      tertiary: V360Colors.info500,
      onTertiary: V360Colors.neutral0,
      tertiaryContainer: V360Colors.info50,
      onTertiaryContainer: V360Colors.info700,
      error: V360Colors.danger500,
      onError: V360Colors.neutral0,
      errorContainer: V360Colors.danger50,
      onErrorContainer: V360Colors.danger700,
      surface: V360Colors.neutral0,
      onSurface: V360Colors.gray800,
      surfaceContainerLowest: V360Colors.neutral0,
      surfaceContainerLow: V360Colors.neutral50,
      surfaceContainer: V360Colors.neutral100,
      surfaceContainerHigh: V360Colors.neutral200,
      surfaceContainerHighest: V360Colors.neutral300,
      onSurfaceVariant: V360Colors.gray500,
      outline: V360Colors.gray300,
      outlineVariant: V360Colors.gray200,
      shadow: Color(0x1A000000),
      scrim: Color(0x99000000),
      inverseSurface: V360Colors.gray900,
      onInverseSurface: V360Colors.gray50,
      inversePrimary: V360Colors.primary300,
    );
    return _build(scheme, Brightness.light);
  }

  static ThemeData dark() {
    final ColorScheme scheme = const ColorScheme(
      brightness: Brightness.dark,
      primary: V360Colors.primary400,
      onPrimary: V360Colors.neutral900,
      primaryContainer: V360Colors.primary800,
      onPrimaryContainer: V360Colors.primary100,
      secondary: V360Colors.neutral200,
      onSecondary: V360Colors.neutral900,
      secondaryContainer: V360Colors.neutral800,
      onSecondaryContainer: V360Colors.neutral100,
      tertiary: V360Colors.info500,
      onTertiary: V360Colors.neutral900,
      tertiaryContainer: V360Colors.info700,
      onTertiaryContainer: V360Colors.info50,
      error: V360Colors.danger500,
      onError: V360Colors.neutral0,
      errorContainer: V360Colors.danger700,
      onErrorContainer: V360Colors.danger50,
      surface: V360Colors.neutral900,
      onSurface: V360Colors.neutral100,
      surfaceContainerLowest: Color(0xFF0B1220),
      surfaceContainerLow: V360Colors.neutral900,
      surfaceContainer: V360Colors.neutral800,
      surfaceContainerHigh: V360Colors.neutral700,
      surfaceContainerHighest: V360Colors.neutral600,
      onSurfaceVariant: V360Colors.neutral400,
      outline: V360Colors.neutral600,
      outlineVariant: V360Colors.neutral700,
      shadow: Color(0x66000000),
      scrim: Color(0xCC000000),
      inverseSurface: V360Colors.neutral100,
      onInverseSurface: V360Colors.neutral900,
      inversePrimary: V360Colors.primary600,
    );
    return _build(scheme, Brightness.dark);
  }

  static ThemeData _build(ColorScheme scheme, Brightness brightness) {
    final TextTheme baseText = brightness == Brightness.light
        ? Typography.blackMountainView
        : Typography.whiteMountainView;
    final TextTheme text = baseText.copyWith(
      displayLarge: baseText.displayLarge?.copyWith(
        fontFamily: _fontFamily,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      displayMedium: baseText.displayMedium?.copyWith(
        fontFamily: _fontFamily,
        fontWeight: FontWeight.w700,
      ),
      headlineLarge: baseText.headlineLarge?.copyWith(
        fontFamily: _fontFamily,
        fontWeight: FontWeight.w700,
        fontSize: 32,
        letterSpacing: -0.3,
      ),
      headlineMedium: baseText.headlineMedium?.copyWith(
        fontFamily: _fontFamily,
        fontWeight: FontWeight.w700,
        fontSize: 24,
      ),
      headlineSmall: baseText.headlineSmall?.copyWith(
        fontFamily: _fontFamily,
        fontWeight: FontWeight.w600,
        fontSize: 20,
      ),
      titleLarge: baseText.titleLarge?.copyWith(
        fontFamily: _fontFamily,
        fontWeight: FontWeight.w600,
        fontSize: 18,
      ),
      titleMedium: baseText.titleMedium?.copyWith(
        fontFamily: _fontFamily,
        fontWeight: FontWeight.w600,
        fontSize: 16,
      ),
      titleSmall: baseText.titleSmall?.copyWith(
        fontFamily: _fontFamily,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      bodyLarge: baseText.bodyLarge?.copyWith(
        fontFamily: _fontFamily,
        fontSize: 16,
        height: 1.5,
      ),
      bodyMedium: baseText.bodyMedium?.copyWith(
        fontFamily: _fontFamily,
        fontSize: 14,
        height: 1.5,
      ),
      bodySmall: baseText.bodySmall?.copyWith(
        fontFamily: _fontFamily,
        fontSize: 12,
        height: 1.5,
      ),
      labelLarge: baseText.labelLarge?.copyWith(
        fontFamily: _fontFamily,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      labelMedium: baseText.labelMedium?.copyWith(
        fontFamily: _fontFamily,
        fontWeight: FontWeight.w500,
        fontSize: 12,
      ),
      labelSmall: baseText.labelSmall?.copyWith(
        fontFamily: _fontFamily,
        fontWeight: FontWeight.w500,
        fontSize: 11,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: _fontFamily,
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: brightness == Brightness.light
            ? SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent)
            : SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(V360Radius.xl),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: V360Spacing.s5),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(V360Radius.lg),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: V360Spacing.s5),
          textStyle: text.labelLarge,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(V360Radius.lg),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: V360Spacing.s5),
          textStyle: text.labelLarge,
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(V360Radius.lg),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: V360Spacing.s3),
          textStyle: text.labelLarge,
          foregroundColor: scheme.primary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.light
            ? V360Colors.neutral50
            : V360Colors.neutral800,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: V360Spacing.s4,
          vertical: V360Spacing.s4,
        ),
        hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        labelStyle: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(V360Radius.lg),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(V360Radius.lg),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(V360Radius.lg),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(V360Radius.lg),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(V360Radius.lg),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 68,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return text.labelSmall?.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: scheme.outlineVariant,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(V360Radius.xxl),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(V360Radius.xl),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainer,
        selectedColor: scheme.primaryContainer,
        labelStyle: text.labelMedium,
        padding: const EdgeInsets.symmetric(
          horizontal: V360Spacing.s3,
          vertical: V360Spacing.s1,
        ),
        shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(V360Radius.lg),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: V360Colors.primary500,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.onPrimary;
          return brightness == Brightness.light
              ? V360Colors.neutral0
              : V360Colors.neutral400;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return scheme.outlineVariant;
        }),
      ),
      iconTheme: IconThemeData(color: scheme.onSurface, size: 22),
      splashFactory: InkRipple.splashFactory,
    );
  }
}
