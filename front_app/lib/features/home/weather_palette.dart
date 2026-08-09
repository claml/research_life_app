import 'dart:ui';

import '../../core/models/weather_models.dart';

/// 天气视觉调色板：首页天气背景与画布绘制的数据语义色。
///
/// 这些颜色表达「天气状况」这一数据含义（晴黄、雨雪蓝、沙尘棕），
/// 刻意独立于主题令牌，不随换主题变化；与面板底的融合由
/// `_weatherGradientColors` 中的 `Color.lerp(tokens.*)` 完成。
/// 见 docs/frontend_style_guide.md §2.5。
abstract final class WeatherPalette {
  // ---- 天气渐变主色调（与令牌面板色 lerp 后作为背景） ----
  static const Color clearDay = Color(0xFFFFF5D6);
  static const Color clearNight = Color(0xFFEAF0FA);
  static const Color cloudy = Color(0xFFE8EEF2);
  static const Color fog = Color(0xFFE9ECE8);
  static const Color dust = Color(0xFFE9DCC4);
  static const Color drizzle = Color(0xFFE5EEF4);
  static const Color rain = Color(0xFFDDEBF4);
  static const Color snow = Color(0xFFF3F8FA);
  static const Color thunderstorm = Color(0xFFD8E2EA);

  // ---- 画布绘制色 ----
  static const Color sunCore = Color(0xFFFFD36D);
  static const Color sunGlow = Color(0xFFFFF3C4);
  static const Color moonCore = Color(0xFFE7EDF8);
  static const Color cloudShadow = Color(0xFF7C8A94);
  static const Color rainDrop = Color(0xFF5D7F98);
  static const Color rainSplash = Color(0xFF6E8FA6);
  static const Color dustHaze = Color(0xFFC9A06A);
  static const Color dustStreak = Color(0xFFA98352);
  static const Color lightningBolt = Color(0xFFFFF6B8);

  /// 天气状况对应的渐变主色调；[WeatherCondition.unknown] 返回 null，
  /// 由调用方回退到令牌色（tokens.panelAccent）。
  static Color? tintFor(WeatherCondition condition, {required bool isDay}) {
    return switch (condition) {
      WeatherCondition.clear => isDay ? clearDay : clearNight,
      WeatherCondition.cloudy => cloudy,
      WeatherCondition.fog => fog,
      WeatherCondition.dust => dust,
      WeatherCondition.drizzle => drizzle,
      WeatherCondition.rain => rain,
      WeatherCondition.snow => snow,
      WeatherCondition.thunderstorm => thunderstorm,
      WeatherCondition.unknown => null,
    };
  }
}
