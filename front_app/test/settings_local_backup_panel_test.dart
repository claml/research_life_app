import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/app/local_services_scope.dart';
import 'package:research_life/features/settings/widgets/local_backup_panel.dart';
import 'package:research_life/services/agent/ai_credential_store.dart';
import 'package:research_life/services/agent/ai_profile_repository.dart';
import 'package:research_life/services/agent/ai_runtime_services.dart';
import 'package:research_life/services/agent/openai_compatible_chat_client.dart';
import 'package:research_life/services/database/repositories/agent_chat_repository.dart';
import 'package:research_life/services/database/repositories/preferences_repository.dart';
import 'package:research_life/services/storage/backup_manifest.dart';
import 'package:research_life/services/storage/backup_service.dart';
import 'package:research_life/state/local_backup_controller.dart';

void main() {
  testWidgets('backup panel shows restrained local actions and latest backup', (
    tester,
  ) async {
    final backupService = _PanelBackupService();
    final controller = LocalBackupController(
      backupService: backupService,
      migrationPreferences: _PanelMigrationPreferences(),
      flushLocalWrites: () async {},
      restoreRuntime: (_) async => backupService.restoreResult,
    );
    addTearDown(controller.dispose);
    await controller.createManualBackup();
    final aiServices = AiRuntimeServices(
      profiles: _PanelAiProfileStore(),
      credentials: _PanelAiCredentialStore(),
      chats: _PanelAgentChatStore(),
      client: OpenAiCompatibleChatClient(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LocalServicesScope(
          backupController: controller,
          aiServices: aiServices,
          restoreAndRestart: (_) async => backupService.restoreResult,
          child: Builder(
            builder: (context) {
              expect(LocalServicesScope.read(context).aiServices, aiServices);
              return const Scaffold(body: LocalBackupPanel());
            },
          ),
        ),
      ),
    );

    expect(find.text('备份与恢复'), findsOneWidget);
    expect(find.text('立即备份'), findsOneWidget);
    expect(find.text('打开备份目录'), findsOneWidget);
    expect(find.text('恢复备份'), findsOneWidget);
    expect(find.textContaining('2026-08-09'), findsOneWidget);
    expect(find.textContaining(r'C:\backups'), findsOneWidget);
    expect(find.text('登录'), findsNothing);
    expect(find.text('云同步'), findsNothing);
  });
}

class _PanelMigrationPreferences implements LocalMigrationPreferences {
  @override
  Future<void> invalidateLocalMigrationBackupRecord() async {}

  @override
  Future<bool> loadLocalMigrationBackupComplete() async => false;

  @override
  Future<String?> loadLocalMigrationBackupPath() async => null;

  @override
  Future<void> saveLocalMigrationBackupRecord(String path) async {}
}

class _PanelAiProfileStore extends Fake implements AiProfileStore {}

class _PanelAiCredentialStore extends Fake implements AiCredentialStore {}

class _PanelAgentChatStore extends Fake implements AgentChatStore {}

class _PanelBackupService extends Fake implements BackupService {
  final List<BackupCreateResult> _backups = [];

  BackupRestoreResult get restoreResult => BackupRestoreResult(
    restoredBackupDirectory: Directory(r'C:\backups\manual-1'),
    safetyBackup: _backups.single,
  );

  @override
  Future<BackupCreateResult> createBackup({
    BackupPurpose purpose = BackupPurpose.manual,
  }) async {
    final manifest = BackupManifest(
      purpose: purpose,
      appVersion: 'test',
      createdAt: DateTime(2026, 8, 9, 12, 30),
      schemaVersion: 1,
      workspacePath: r'C:\workspace',
      databaseFile: const BackupFileInfo(
        path: 'research_life.sqlite',
        sha256: 'db-sha',
        sizeBytes: 1,
      ),
      preferencesFile: const BackupFileInfo(
        path: 'preferences.json',
        sha256: 'preferences-sha',
        sizeBytes: 1,
      ),
    );
    final result = BackupCreateResult(
      directory: Directory(r'C:\backups\manual-1'),
      manifest: manifest,
      purpose: purpose,
    );
    _backups.add(result);
    return result;
  }

  @override
  Future<List<BackupCreateResult>> listBackups() async =>
      List.unmodifiable(_backups.reversed);
}
