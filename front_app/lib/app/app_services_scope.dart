import 'package:flutter/widgets.dart';

import '../services/sync/file_sync_engine.dart';

class AppServicesScope extends InheritedWidget {
  const AppServicesScope({
    required this.fileSyncEngine,
    required super.child,
    super.key,
  });

  final FileSyncEngine fileSyncEngine;

  static AppServicesScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppServicesScope>();
    assert(scope != null, 'AppServicesScope is missing in the widget tree.');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppServicesScope oldWidget) {
    return fileSyncEngine != oldWidget.fileSyncEngine;
  }
}
