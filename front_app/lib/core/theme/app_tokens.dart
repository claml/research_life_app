import 'dart:ui';

import 'package:flutter/material.dart';

abstract final class AppLayout {
  static const double pageHeaderMinHeight = 138;
  static const double pageHorizontalPadding = 28;
  static const double pageContentTopPadding = 28;
  static const double workspaceTabHeight = 30;
  static const Duration quickMotion = Duration(milliseconds: 180);
}

enum AppColorTheme { green, pink, blue, ojBlue, white, black }

extension AppColorThemeDetails on AppColorTheme {
  String get storageValue => name;

  String get label => switch (this) {
    AppColorTheme.ojBlue => 'OJ 蓝白',
    AppColorTheme.green => '绿色',
    AppColorTheme.pink => '粉色',
    AppColorTheme.blue => '蓝色',
    AppColorTheme.white => '白色',
    AppColorTheme.black => '黑色',
  };

  Brightness get brightness => switch (this) {
    AppColorTheme.black => Brightness.dark,
    _ => Brightness.light,
  };

  AppTokens get tokens => switch (this) {
    AppColorTheme.ojBlue => AppTokens.ojBlue,
    AppColorTheme.green => AppTokens.green,
    AppColorTheme.pink => AppTokens.pink,
    AppColorTheme.blue => AppTokens.blue,
    AppColorTheme.white => AppTokens.white,
    AppColorTheme.black => AppTokens.black,
  };

  static AppColorTheme fromStorageValue(String? value) {
    final normalized = value?.trim().toLowerCase();
    return AppColorTheme.values.firstWhere(
      (theme) => theme.storageValue == normalized,
      orElse: () => AppColorTheme.green,
    );
  }
}

@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.canvas,
    required this.backdropTop,
    required this.backdropMiddle,
    required this.backdropBottom,
    required this.shellSurface,
    required this.shellBorder,
    required this.sidebarSurface,
    required this.sidebarSurfaceStrong,
    required this.sidebarSelected,
    required this.panelSurface,
    required this.panelSubtle,
    required this.panelAccent,
    required this.insetSurface,
    required this.borderSoft,
    required this.borderFaint,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentHover,
    required this.accentSoft,
    required this.warmAccent,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.radiusSmall,
    required this.radiusMedium,
    required this.radiusLarge,
    required this.radiusXLarge,
    required this.shadowSm,
    required this.shadowMd,
  });

  final Color canvas;
  final Color backdropTop;
  final Color backdropMiddle;
  final Color backdropBottom;
  final Color shellSurface;
  final Color shellBorder;
  final Color sidebarSurface;
  final Color sidebarSurfaceStrong;
  final Color sidebarSelected;
  final Color panelSurface;
  final Color panelSubtle;
  final Color panelAccent;
  final Color insetSurface;
  final Color borderSoft;
  final Color borderFaint;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color accentHover;
  final Color accentSoft;
  final Color warmAccent;

  /// 语义色：独立于主题强调色，浅色主题间取值一致，仅暗色主题做明度适配。
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final double radiusSmall;
  final double radiusMedium;
  final double radiusLarge;
  final double radiusXLarge;
  final List<BoxShadow> shadowSm;
  final List<BoxShadow> shadowMd;

  /// 普通提示语义色，按规范复用强调色系。
  Color get info => accent;
  Color get infoSoft => accentSoft;

  static const AppTokens green = AppTokens(
    canvas: Color(0xFFF5F7F2),
    backdropTop: Color(0xFFF8FBF7),
    backdropMiddle: Color(0xFFEEF5F0),
    backdropBottom: Color(0xFFF9FAF8),
    shellSurface: Color(0xFFFDFEFC),
    shellBorder: Color(0xD9FFFFFF),
    sidebarSurface: Color(0xFF18392C),
    sidebarSurfaceStrong: Color(0xFF11291F),
    sidebarSelected: Color(0xFFE8F1E8),
    panelSurface: Color(0xFFFFFFFF),
    panelSubtle: Color(0xFFF4F8F3),
    panelAccent: Color(0xFFEAF4EB),
    insetSurface: Color(0xFFFBFCFA),
    borderSoft: Color(0xFFDDE6DE),
    borderFaint: Color(0xFFE8EEE8),
    textPrimary: Color(0xFF183129),
    textSecondary: Color(0xFF617066),
    textMuted: Color(0xFF8B978F),
    accent: Color(0xFF2F6B4B),
    accentHover: Color(0xFF255A3F),
    accentSoft: Color(0xFFDCEBDE),
    warmAccent: Color(0xFFC9A56A),
    success: Color(0xFF2E7D4F),
    successSoft: Color(0xFFE1F0E7),
    warning: Color(0xFFC98A2D),
    warningSoft: Color(0xFFF7EEDB),
    danger: Color(0xFFC04545),
    dangerSoft: Color(0xFFF6E3E3),
    radiusSmall: 12,
    radiusMedium: 16,
    radiusLarge: 20,
    radiusXLarge: 24,
    shadowSm: [
      BoxShadow(color: Color(0x0F10241C), blurRadius: 18, offset: Offset(0, 6)),
    ],
    shadowMd: [
      BoxShadow(
        color: Color(0x1810241C),
        blurRadius: 32,
        offset: Offset(0, 14),
      ),
    ],
  );

  static const AppTokens light = green;

  static const AppTokens pink = AppTokens(
    canvas: Color(0xFFFBF5F8),
    backdropTop: Color(0xFFFFFAFC),
    backdropMiddle: Color(0xFFF8EDF3),
    backdropBottom: Color(0xFFFCF8FA),
    shellSurface: Color(0xFFFFFCFD),
    shellBorder: Color(0xD9FFFFFF),
    sidebarSurface: Color(0xFF4C2035),
    sidebarSurfaceStrong: Color(0xFF351525),
    sidebarSelected: Color(0xFFF6E6EE),
    panelSurface: Color(0xFFFFFFFF),
    panelSubtle: Color(0xFFFAF0F5),
    panelAccent: Color(0xFFF7E6EF),
    insetSurface: Color(0xFFFFFAFC),
    borderSoft: Color(0xFFE8D4DF),
    borderFaint: Color(0xFFF0E2EA),
    textPrimary: Color(0xFF321F29),
    textSecondary: Color(0xFF75606A),
    textMuted: Color(0xFF9B8791),
    accent: Color(0xFFB23C72),
    accentHover: Color(0xFF96305F),
    accentSoft: Color(0xFFF0D6E3),
    warmAccent: Color(0xFFC59858),
    success: Color(0xFF2E7D4F),
    successSoft: Color(0xFFE1F0E7),
    warning: Color(0xFFC98A2D),
    warningSoft: Color(0xFFF7EEDB),
    danger: Color(0xFFC04545),
    dangerSoft: Color(0xFFF6E3E3),
    radiusSmall: 12,
    radiusMedium: 16,
    radiusLarge: 20,
    radiusXLarge: 24,
    shadowSm: [
      BoxShadow(color: Color(0x12321F29), blurRadius: 18, offset: Offset(0, 6)),
    ],
    shadowMd: [
      BoxShadow(
        color: Color(0x1A321F29),
        blurRadius: 32,
        offset: Offset(0, 14),
      ),
    ],
  );

  static const AppTokens blue = AppTokens(
    canvas: Color(0xFFF3F7FB),
    backdropTop: Color(0xFFF8FBFF),
    backdropMiddle: Color(0xFFEAF2FA),
    backdropBottom: Color(0xFFF8FAFC),
    shellSurface: Color(0xFFFCFEFF),
    shellBorder: Color(0xD9FFFFFF),
    sidebarSurface: Color(0xFF173654),
    sidebarSurfaceStrong: Color(0xFF10263C),
    sidebarSelected: Color(0xFFE5EFF8),
    panelSurface: Color(0xFFFFFFFF),
    panelSubtle: Color(0xFFF0F6FB),
    panelAccent: Color(0xFFE6F0FA),
    insetSurface: Color(0xFFFAFCFE),
    borderSoft: Color(0xFFD4E0EC),
    borderFaint: Color(0xFFE2EBF3),
    textPrimary: Color(0xFF182C3E),
    textSecondary: Color(0xFF5E6D7A),
    textMuted: Color(0xFF8795A1),
    accent: Color(0xFF256AA6),
    accentHover: Color(0xFF1D5789),
    accentSoft: Color(0xFFD6E7F5),
    warmAccent: Color(0xFFC29255),
    success: Color(0xFF2E7D4F),
    successSoft: Color(0xFFE1F0E7),
    warning: Color(0xFFC98A2D),
    warningSoft: Color(0xFFF7EEDB),
    danger: Color(0xFFC04545),
    dangerSoft: Color(0xFFF6E3E3),
    radiusSmall: 12,
    radiusMedium: 16,
    radiusLarge: 20,
    radiusXLarge: 24,
    shadowSm: [
      BoxShadow(color: Color(0x11182C3E), blurRadius: 18, offset: Offset(0, 6)),
    ],
    shadowMd: [
      BoxShadow(
        color: Color(0x1A182C3E),
        blurRadius: 32,
        offset: Offset(0, 14),
      ),
    ],
  );

  static const AppTokens ojBlue = AppTokens(
    canvas: Color(0xFFFFFFFF),
    backdropTop: Color(0xFFFEFEFE),
    backdropMiddle: Color(0xFFF7FAFF),
    backdropBottom: Color(0xFFFFFFFF),
    shellSurface: Color(0xFFFDFEFF),
    shellBorder: Color(0xFFE5E6EB),
    sidebarSurface: Color(0xFF102A43),
    sidebarSurfaceStrong: Color(0xFF0B1F33),
    sidebarSelected: Color(0xFFEAF3FF),
    panelSurface: Color(0xFFFFFFFF),
    panelSubtle: Color(0xFFF7FAFF),
    panelAccent: Color(0xFFF2F8FF),
    insetSurface: Color(0xFFFFFFFF),
    borderSoft: Color(0xFFD9E7FB),
    borderFaint: Color(0xFFE5E6EB),
    textPrimary: Color(0xFF1D2129),
    textSecondary: Color(0xFF4E5969),
    textMuted: Color(0xFF86909C),
    accent: Color(0xFF165DFF),
    accentHover: Color(0xFF0E49D2),
    accentSoft: Color(0xFFEAF3FF),
    warmAccent: Color(0xFFD69220),
    success: Color(0xFF2E7D4F),
    successSoft: Color(0xFFE1F0E7),
    warning: Color(0xFFC98A2D),
    warningSoft: Color(0xFFF7EEDB),
    danger: Color(0xFFC04545),
    dangerSoft: Color(0xFFF6E3E3),
    radiusSmall: 10,
    radiusMedium: 12,
    radiusLarge: 16,
    radiusXLarge: 22,
    shadowSm: [
      BoxShadow(color: Color(0x0F102A43), blurRadius: 18, offset: Offset(0, 8)),
    ],
    shadowMd: [
      BoxShadow(
        color: Color(0x1A102A43),
        blurRadius: 24,
        offset: Offset(0, 12),
      ),
    ],
  );

  static const AppTokens white = AppTokens(
    canvas: Color(0xFFF7F7F5),
    backdropTop: Color(0xFFFFFFFF),
    backdropMiddle: Color(0xFFF0F1EF),
    backdropBottom: Color(0xFFFAFAF8),
    shellSurface: Color(0xFFFFFFFF),
    shellBorder: Color(0xD9FFFFFF),
    sidebarSurface: Color(0xFF2B2F33),
    sidebarSurfaceStrong: Color(0xFF1D2024),
    sidebarSelected: Color(0xFFEDEDEA),
    panelSurface: Color(0xFFFFFFFF),
    panelSubtle: Color(0xFFF2F2EF),
    panelAccent: Color(0xFFE9E9E5),
    insetSurface: Color(0xFFFBFBFA),
    borderSoft: Color(0xFFDCDDD8),
    borderFaint: Color(0xFFE8E8E4),
    textPrimary: Color(0xFF202326),
    textSecondary: Color(0xFF656A6E),
    textMuted: Color(0xFF91969A),
    accent: Color(0xFF30363D),
    accentHover: Color(0xFF20262C),
    accentSoft: Color(0xFFE1E3E5),
    warmAccent: Color(0xFFB28A4A),
    success: Color(0xFF2E7D4F),
    successSoft: Color(0xFFE1F0E7),
    warning: Color(0xFFC98A2D),
    warningSoft: Color(0xFFF7EEDB),
    danger: Color(0xFFC04545),
    dangerSoft: Color(0xFFF6E3E3),
    radiusSmall: 12,
    radiusMedium: 16,
    radiusLarge: 20,
    radiusXLarge: 24,
    shadowSm: [
      BoxShadow(color: Color(0x11202326), blurRadius: 18, offset: Offset(0, 6)),
    ],
    shadowMd: [
      BoxShadow(
        color: Color(0x18202326),
        blurRadius: 32,
        offset: Offset(0, 14),
      ),
    ],
  );

  static const AppTokens black = AppTokens(
    canvas: Color(0xFF101214),
    backdropTop: Color(0xFF171A1D),
    backdropMiddle: Color(0xFF111417),
    backdropBottom: Color(0xFF0C0E10),
    shellSurface: Color(0xFF15181B),
    shellBorder: Color(0x331F252B),
    sidebarSurface: Color(0xFF070809),
    sidebarSurfaceStrong: Color(0xFF030405),
    sidebarSelected: Color(0xFF252A30),
    panelSurface: Color(0xFF181B1F),
    panelSubtle: Color(0xFF20242A),
    panelAccent: Color(0xFF262B31),
    insetSurface: Color(0xFF121519),
    borderSoft: Color(0xFF333940),
    borderFaint: Color(0xFF252B31),
    textPrimary: Color(0xFFEDEFF1),
    textSecondary: Color(0xFFB8BFC6),
    textMuted: Color(0xFF858E97),
    accent: Color(0xFF63758A),
    accentHover: Color(0xFF7A8B9E),
    accentSoft: Color(0xFF2B333D),
    warmAccent: Color(0xFFC3A46C),
    success: Color(0xFF5CB98A),
    successSoft: Color(0xFF22352B),
    warning: Color(0xFFD9A84E),
    warningSoft: Color(0xFF37301F),
    danger: Color(0xFFD06B6B),
    dangerSoft: Color(0xFF382526),
    radiusSmall: 12,
    radiusMedium: 16,
    radiusLarge: 20,
    radiusXLarge: 24,
    shadowSm: [
      BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 6)),
    ],
    shadowMd: [
      BoxShadow(
        color: Color(0x99000000),
        blurRadius: 32,
        offset: Offset(0, 14),
      ),
    ],
  );

  @override
  AppTokens copyWith({
    Color? canvas,
    Color? backdropTop,
    Color? backdropMiddle,
    Color? backdropBottom,
    Color? shellSurface,
    Color? shellBorder,
    Color? sidebarSurface,
    Color? sidebarSurfaceStrong,
    Color? sidebarSelected,
    Color? panelSurface,
    Color? panelSubtle,
    Color? panelAccent,
    Color? insetSurface,
    Color? borderSoft,
    Color? borderFaint,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? accent,
    Color? accentHover,
    Color? accentSoft,
    Color? warmAccent,
    Color? success,
    Color? successSoft,
    Color? warning,
    Color? warningSoft,
    Color? danger,
    Color? dangerSoft,
    double? radiusSmall,
    double? radiusMedium,
    double? radiusLarge,
    double? radiusXLarge,
    List<BoxShadow>? shadowSm,
    List<BoxShadow>? shadowMd,
  }) {
    return AppTokens(
      canvas: canvas ?? this.canvas,
      backdropTop: backdropTop ?? this.backdropTop,
      backdropMiddle: backdropMiddle ?? this.backdropMiddle,
      backdropBottom: backdropBottom ?? this.backdropBottom,
      shellSurface: shellSurface ?? this.shellSurface,
      shellBorder: shellBorder ?? this.shellBorder,
      sidebarSurface: sidebarSurface ?? this.sidebarSurface,
      sidebarSurfaceStrong: sidebarSurfaceStrong ?? this.sidebarSurfaceStrong,
      sidebarSelected: sidebarSelected ?? this.sidebarSelected,
      panelSurface: panelSurface ?? this.panelSurface,
      panelSubtle: panelSubtle ?? this.panelSubtle,
      panelAccent: panelAccent ?? this.panelAccent,
      insetSurface: insetSurface ?? this.insetSurface,
      borderSoft: borderSoft ?? this.borderSoft,
      borderFaint: borderFaint ?? this.borderFaint,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      accent: accent ?? this.accent,
      accentHover: accentHover ?? this.accentHover,
      accentSoft: accentSoft ?? this.accentSoft,
      warmAccent: warmAccent ?? this.warmAccent,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      radiusSmall: radiusSmall ?? this.radiusSmall,
      radiusMedium: radiusMedium ?? this.radiusMedium,
      radiusLarge: radiusLarge ?? this.radiusLarge,
      radiusXLarge: radiusXLarge ?? this.radiusXLarge,
      shadowSm: shadowSm ?? this.shadowSm,
      shadowMd: shadowMd ?? this.shadowMd,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) {
      return this;
    }

    return AppTokens(
      canvas: Color.lerp(canvas, other.canvas, t) ?? canvas,
      backdropTop: Color.lerp(backdropTop, other.backdropTop, t) ?? backdropTop,
      backdropMiddle:
          Color.lerp(backdropMiddle, other.backdropMiddle, t) ?? backdropMiddle,
      backdropBottom:
          Color.lerp(backdropBottom, other.backdropBottom, t) ?? backdropBottom,
      shellSurface:
          Color.lerp(shellSurface, other.shellSurface, t) ?? shellSurface,
      shellBorder: Color.lerp(shellBorder, other.shellBorder, t) ?? shellBorder,
      sidebarSurface:
          Color.lerp(sidebarSurface, other.sidebarSurface, t) ?? sidebarSurface,
      sidebarSurfaceStrong:
          Color.lerp(sidebarSurfaceStrong, other.sidebarSurfaceStrong, t) ??
          sidebarSurfaceStrong,
      sidebarSelected:
          Color.lerp(sidebarSelected, other.sidebarSelected, t) ??
          sidebarSelected,
      panelSurface:
          Color.lerp(panelSurface, other.panelSurface, t) ?? panelSurface,
      panelSubtle: Color.lerp(panelSubtle, other.panelSubtle, t) ?? panelSubtle,
      panelAccent: Color.lerp(panelAccent, other.panelAccent, t) ?? panelAccent,
      insetSurface:
          Color.lerp(insetSurface, other.insetSurface, t) ?? insetSurface,
      borderSoft: Color.lerp(borderSoft, other.borderSoft, t) ?? borderSoft,
      borderFaint: Color.lerp(borderFaint, other.borderFaint, t) ?? borderFaint,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary:
          Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      textMuted: Color.lerp(textMuted, other.textMuted, t) ?? textMuted,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      accentHover: Color.lerp(accentHover, other.accentHover, t) ?? accentHover,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t) ?? accentSoft,
      warmAccent: Color.lerp(warmAccent, other.warmAccent, t) ?? warmAccent,
      success: Color.lerp(success, other.success, t) ?? success,
      successSoft: Color.lerp(successSoft, other.successSoft, t) ?? successSoft,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t) ?? warningSoft,
      danger: Color.lerp(danger, other.danger, t) ?? danger,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t) ?? dangerSoft,
      radiusSmall: lerpDouble(radiusSmall, other.radiusSmall, t) ?? radiusSmall,
      radiusMedium:
          lerpDouble(radiusMedium, other.radiusMedium, t) ?? radiusMedium,
      radiusLarge: lerpDouble(radiusLarge, other.radiusLarge, t) ?? radiusLarge,
      radiusXLarge:
          lerpDouble(radiusXLarge, other.radiusXLarge, t) ?? radiusXLarge,
      shadowSm: t < 0.5 ? shadowSm : other.shadowSm,
      shadowMd: t < 0.5 ? shadowMd : other.shadowMd,
    );
  }
}

extension AppTokensContext on BuildContext {
  AppTokens get tokens =>
      Theme.of(this).extension<AppTokens>() ?? AppTokens.light;
}
