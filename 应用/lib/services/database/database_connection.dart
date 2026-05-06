import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../storage/local_workspace_service.dart';

QueryExecutor openDatabaseConnection(LocalWorkspaceService workspaceService) {
  return LazyDatabase(() async {
    final databaseFile = await workspaceService.resolveDatabaseFile();
    await databaseFile.parent.create(recursive: true);
    return NativeDatabase.createInBackground(databaseFile);
  });
}
