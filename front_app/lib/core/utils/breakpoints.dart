import 'package:flutter/widgets.dart';

/// 页面级断点，见 docs/frontend_style_guide.md §4.4。
///
/// - < [compact]：单栏堆叠，侧栏折叠
/// - [compact] ~ [wide)：常规桌面窗口
/// - ≥ [wide]：宽屏，内容最大宽度限宽居中
///
/// 页面级布局只允许引用这三档；组件内部的小断点（如 SectionCard 的
/// 620）允许存在，但需在处注释说明用途。
abstract final class AppBreakpoints {
  static const double compact = 760;
  static const double wide = 1200;

  /// 宽屏下内容区的最大宽度（工作面板模式限宽居中）。
  static const double contentMaxWidth = 1080;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compact;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= wide;
}
