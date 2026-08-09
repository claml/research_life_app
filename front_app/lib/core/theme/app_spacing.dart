import 'package:flutter/widgets.dart';

/// 间距令牌，以 4 为基数。见 docs/frontend_style_guide.md §4.1。
///
/// 约定：
/// - 窗口外边距 / 壳层内边距 / 卡片内边距 → [x5]
/// - 卡片之间间距 → [x4] ~ [x5]
/// - 标题与内容间距 → [x4]
/// - 行内元素间距 → [x2] ~ [x3]
/// - 紧凑列表行距 → [x1] ~ [x2]
///
/// 新代码统一引用本类，不再写间距字面量；旧代码渐进替换。
abstract final class AppSpacing {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;

  static const EdgeInsets allX1 = EdgeInsets.all(x1);
  static const EdgeInsets allX2 = EdgeInsets.all(x2);
  static const EdgeInsets allX3 = EdgeInsets.all(x3);
  static const EdgeInsets allX4 = EdgeInsets.all(x4);
  static const EdgeInsets allX5 = EdgeInsets.all(x5);
  static const EdgeInsets allX6 = EdgeInsets.all(x6);
  static const EdgeInsets allX8 = EdgeInsets.all(x8);

  static const SizedBox gapX1 = SizedBox(width: x1, height: x1);
  static const SizedBox gapX2 = SizedBox(width: x2, height: x2);
  static const SizedBox gapX3 = SizedBox(width: x3, height: x3);
  static const SizedBox gapX4 = SizedBox(width: x4, height: x4);
  static const SizedBox gapX5 = SizedBox(width: x5, height: x5);
  static const SizedBox gapX6 = SizedBox(width: x6, height: x6);
  static const SizedBox gapX8 = SizedBox(width: x8, height: x8);

  static const SizedBox hGapX1 = SizedBox(width: x1);
  static const SizedBox hGapX2 = SizedBox(width: x2);
  static const SizedBox hGapX3 = SizedBox(width: x3);
  static const SizedBox hGapX4 = SizedBox(width: x4);
  static const SizedBox hGapX5 = SizedBox(width: x5);
  static const SizedBox hGapX6 = SizedBox(width: x6);
  static const SizedBox hGapX8 = SizedBox(width: x8);

  static const SizedBox vGapX1 = SizedBox(height: x1);
  static const SizedBox vGapX2 = SizedBox(height: x2);
  static const SizedBox vGapX3 = SizedBox(height: x3);
  static const SizedBox vGapX4 = SizedBox(height: x4);
  static const SizedBox vGapX5 = SizedBox(height: x5);
  static const SizedBox vGapX6 = SizedBox(height: x6);
  static const SizedBox vGapX8 = SizedBox(height: x8);
}
