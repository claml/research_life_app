import 'dart:io';

import 'package:flutter/widgets.dart';

import '../services/agent/ai_runtime_services.dart';
import '../services/storage/backup_service.dart';
import '../state/local_backup_controller.dart';

typedef RestoreAndRestart =
    Future<BackupRestoreResult> Function(Directory backupDirectory);

class LocalServicesScope extends InheritedWidget {
  const LocalServicesScope({
    required this.backupController,
    required this.aiServices,
    required this.restoreAndRestart,
    required super.child,
    super.key,
  });

  final LocalBackupController backupController;
  final AiRuntimeServices aiServices;
  final RestoreAndRestart restoreAndRestart;

  static LocalServicesScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<LocalServicesScope>();
    assert(scope != null, 'LocalServicesScope is missing in the widget tree.');
    return scope!;
  }

  static LocalServicesScope read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<LocalServicesScope>();
    assert(scope != null, 'LocalServicesScope is missing in the widget tree.');
    return scope!;
  }

  @override
  bool updateShouldNotify(LocalServicesScope oldWidget) {
    return backupController != oldWidget.backupController ||
        aiServices != oldWidget.aiServices ||
        restoreAndRestart != oldWidget.restoreAndRestart;
  }
}
