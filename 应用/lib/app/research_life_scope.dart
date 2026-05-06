import 'package:flutter/widgets.dart';

import '../state/research_life_controller.dart';

class ResearchLifeScope extends InheritedNotifier<ResearchLifeController> {
  const ResearchLifeScope({
    required ResearchLifeController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static ResearchLifeController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<ResearchLifeScope>();
    assert(scope != null, 'ResearchLifeScope is missing in the widget tree.');
    return scope!.notifier!;
  }
}
