import 'package:flutter/widgets.dart';

import '../state/auth_controller.dart';

/// 提供 [AuthController]；不随 [ChangeNotifier.notifyListeners] 自动重建子树。
class AuthScope extends InheritedWidget {
  const AuthScope({required this.controller, required super.child, super.key});

  final AuthController controller;

  @override
  bool updateShouldNotify(covariant AuthScope oldWidget) {
    return oldWidget.controller != controller;
  }

  static AuthController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AuthScope>();
    assert(scope != null, 'AuthScope is missing in the widget tree.');
    return scope!.controller;
  }

  static AuthController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AuthScope>();
    assert(scope != null, 'AuthScope is missing in the widget tree.');
    return scope!.controller;
  }
}
