import 'package:flutter/material.dart';

import 'app_tokens.dart';

class AppTheme {
  static ThemeData light() {
    return build(AppColorTheme.green);
  }

  static ThemeData build(AppColorTheme colorTheme) {
    final tokens = colorTheme.tokens;
    final brightness = colorTheme.brightness;

    const baseTextTheme = TextTheme(
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        height: 1.15,
        letterSpacing: -0.5,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: -0.3,
      ),
      titleLarge: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        height: 1.25,
      ),
      bodyLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.55,
      ),
      bodyMedium: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.55,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.45,
      ),
      labelLarge: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.2,
      ),
    );

    final scheme =
        ColorScheme.fromSeed(
          seedColor: tokens.accent,
          brightness: brightness,
        ).copyWith(
          primary: tokens.accent,
          onPrimary: Colors.white,
          secondary: tokens.warmAccent,
          surface: tokens.canvas,
          onSurface: tokens.textPrimary,
          outline: tokens.borderSoft,
          outlineVariant: tokens.borderFaint,
          surfaceContainerHighest: tokens.panelSubtle,
        );

    final textTheme = baseTextTheme.apply(
      bodyColor: tokens.textPrimary,
      displayColor: tokens.textPrimary,
      decorationColor: tokens.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: tokens.canvas,
      textTheme: textTheme,
      dividerColor: tokens.borderFaint,
      splashFactory: InkSparkle.splashFactory,
      extensions: [tokens],
      cardTheme: CardThemeData(
        color: tokens.panelSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusLarge),
          side: BorderSide(color: tokens.borderFaint),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusSmall),
            ),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return tokens.accent.withValues(alpha: 0.35);
            }
            if (states.contains(WidgetState.pressed)) {
              return tokens.accentHover;
            }
            return tokens.accent;
          }),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          textStyle: WidgetStatePropertyAll(
            textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          side: WidgetStateProperty.resolveWith((states) {
            final baseColor = states.contains(WidgetState.disabled)
                ? tokens.borderSoft.withValues(alpha: 0.5)
                : tokens.borderSoft;
            return BorderSide(color: baseColor);
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusSmall),
            ),
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return tokens.textMuted;
            }
            if (states.contains(WidgetState.pressed)) {
              return tokens.accentHover;
            }
            return tokens.textPrimary;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return tokens.panelSubtle;
            }
            return Colors.transparent;
          }),
          textStyle: WidgetStatePropertyAll(
            textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusSmall),
            ),
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return tokens.textMuted;
            }
            if (states.contains(WidgetState.pressed)) {
              return tokens.accentHover;
            }
            return tokens.accent;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return tokens.accentSoft.withValues(alpha: 0.55);
            }
            return Colors.transparent;
          }),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusSmall),
            ),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return tokens.accentSoft;
            }
            if (states.contains(WidgetState.hovered)) {
              return tokens.panelSubtle;
            }
            return tokens.insetSurface;
          }),
          foregroundColor: WidgetStatePropertyAll(tokens.textPrimary),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: tokens.borderFaint),
        ),
        side: BorderSide(color: tokens.borderFaint),
        backgroundColor: tokens.insetSurface,
        selectedColor: tokens.accentSoft,
        labelStyle: textTheme.labelLarge?.copyWith(color: tokens.textPrimary),
        secondaryLabelStyle: textTheme.labelLarge?.copyWith(
          color: tokens.textPrimary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.insetSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(color: tokens.textMuted),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          borderSide: BorderSide(color: tokens.borderFaint),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          borderSide: BorderSide(color: tokens.accent, width: 1.4),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          borderSide: BorderSide(color: tokens.borderFaint),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.panelSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusXLarge),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: tokens.sidebarSurfaceStrong.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(tokens.radiusSmall),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: Colors.white),
      ),
    );
  }
}
