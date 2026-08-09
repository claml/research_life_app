import 'package:flutter/widgets.dart';

import '../state/research_life_controller.dart';

/// 提供 [ResearchLifeController]；不订阅 [ChangeNotifier]，避免整树随任意状态刷新。
///
/// 页面内请用 [AnimatedBuilder] / [ListenableBuilder] 监听所需控制器；
/// 仅需读取引用、不需随通知重建时用 [read]。
class ResearchLifeScope extends InheritedWidget {
  const ResearchLifeScope({
    required this.controller,
    required super.child,
    super.key,
  });

  final ResearchLifeController controller;

  @override
  bool updateShouldNotify(covariant ResearchLifeScope oldWidget) {
    return oldWidget.controller != controller;
  }

  static ResearchLifeController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ResearchLifeScope>();
    assert(scope != null, 'ResearchLifeScope is missing in the widget tree.');
    return scope!.controller;
  }

  /// 不注册 Inherited 依赖；须自行通过 [ListenableBuilder] 等订阅 [controller]。
  static ResearchLifeController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ResearchLifeScope>();
    assert(scope != null, 'ResearchLifeScope is missing in the widget tree.');
    return scope!.controller;
  }
}
