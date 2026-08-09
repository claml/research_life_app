import 'dart:ui';

import '../../core/models/app_models.dart';

/// 校园地图调色板：地点标记与地点类别的数据语义色。
///
/// 这些颜色是地图上的「分类标识」（学习绿、餐饮黄、实验紫红……），
/// 刻意独立于主题令牌，在任何主题下保持稳定的类别辨识度；
/// 其中 marker 色同时是用户可选的标记颜色。
/// 见 docs/frontend_style_guide.md §2.5。
abstract final class MapPalette {
  static const Color forest = Color(0xFF2F6B4B);
  static const Color amber = Color(0xFFBC8A2C);
  static const Color slate = Color(0xFF5C6C74);
  static const Color berry = Color(0xFFA24B63);
  static const Color teal = Color(0xFF2C7F8C);
  static const Color campusBlue = Color(0xFF3E6FA5);
  static const Color lavender = Color(0xFF7B5DA7);
  static const Color moss = Color(0xFF7B836F);

  /// 地点类别对应的标识色。
  static Color categoryColor(PlaceCategory category) {
    return switch (category) {
      PlaceCategory.study => forest,
      PlaceCategory.dining => amber,
      PlaceCategory.dormitory => slate,
      PlaceCategory.lab => berry,
      PlaceCategory.sports => teal,
      PlaceCategory.social => lavender,
      PlaceCategory.errands => campusBlue,
      PlaceCategory.other => moss,
    };
  }
}
