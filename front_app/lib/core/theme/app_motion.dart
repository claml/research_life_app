import 'package:flutter/animation.dart';

/// 动效令牌。见 docs/frontend_style_guide.md §5。
///
/// 边界：
/// - 功能动效（hover、展开、切换）：≤ [normal]，不循环、不打断操作。
/// - 氛围动效（天气背景、桌宠）：慢速循环，必须可被设置关闭；
///   `MediaQuery.disableAnimations` 为 true 时降级为静态。
abstract final class AppMotion {
  /// hover、press、tooltip 等即时反馈。
  static const Duration fast = Duration(milliseconds: 120);

  /// 面板展开收起、tab 与导航切换。
  static const Duration normal = Duration(milliseconds: 200);

  /// 页面级过渡、对话框进出。
  static const Duration slow = Duration(milliseconds: 320);

  /// 功能动效默认曲线。
  static const Curve curve = Curves.easeOutCubic;

  /// 循环氛围动画曲线。
  static const Curve loopCurve = Curves.easeInOut;
}
