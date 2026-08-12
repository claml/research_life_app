import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:research_life/services/agent/ai_credential_store.dart';
import 'package:research_life/services/database/app_database.dart';
import 'package:research_life/services/database/database_connection.dart';
import 'package:research_life/services/database/repositories/agent_chat_repository.dart';
import 'package:research_life/services/storage/backup_manifest.dart';
import 'package:research_life/services/storage/backup_service.dart';
import 'package:research_life/services/storage/local_data_operation_coordinator.dart';
import 'package:research_life/services/storage/local_workspace_service.dart';
import 'package:research_life/services/storage/workspace_manifest_service.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('BackupService', () {
    test('creates backup successfully', () async {
      final fixture = await _BackupFixture.create(
        timestamp: DateTime(2026, 5, 13, 9, 10, 11),
      );
      addTearDown(fixture.dispose);
      await fixture.writeDatabaseValue('original');
      await fixture.workspaceService.saveWeeklyPromptTemplate('template');
      await WorkspaceManifestService(
        workspaceService: fixture.workspaceService,
      ).writeManifest(createdAt: DateTime(2026, 5, 13, 9));
      await fixture.writeLocalLibraryFile(
        'library_manifest.json',
        '{"documents":[{"id":"doc_1","isDeleted":true}]}',
      );
      await fixture.writeLocalLibraryFile(
        'annotations.json',
        '{"items":[{"id":"anno_1"}]}',
      );

      final result = await fixture.service.createBackup();

      expect(
        result.directory.path,
        endsWith(
          '${Platform.pathSeparator}.research_life'
          '${Platform.pathSeparator}backups'
          '${Platform.pathSeparator}2026-05-13_091011',
        ),
      );
      expect(
        await File(
          '${result.directory.path}${Platform.pathSeparator}research_life.sqlite',
        ).exists(),
        isTrue,
      );
      expect(
        await File(
          '${result.directory.path}${Platform.pathSeparator}preferences.json',
        ).exists(),
        isTrue,
      );
      expect(
        await File(
          '${result.directory.path}${Platform.pathSeparator}workspace_manifest.json',
        ).exists(),
        isTrue,
      );
      expect(
        await File(
          '${result.directory.path}${Platform.pathSeparator}local_files'
          '${Platform.pathSeparator}library_manifest.json',
        ).exists(),
        isTrue,
      );
      expect(
        await File(
          '${result.directory.path}${Platform.pathSeparator}local_files'
          '${Platform.pathSeparator}annotations.json',
        ).exists(),
        isTrue,
      );
      expect(
        await File(
          '${result.directory.path}${Platform.pathSeparator}backup_manifest.json',
        ).exists(),
        isTrue,
      );
    });

    test('keeps a backup pending until validation succeeds', () async {
      final fixture = await _BackupFixture.create(
        timestamp: DateTime(2026, 8, 9, 10),
      );
      addTearDown(fixture.dispose);
      await fixture.writeDatabaseValue('safe');
      final backupsDirectory = await fixture.workspaceService
          .resolveBackupsDirectory();
      final firstPublishedDirectory = backupsDirectory
          .watch(events: FileSystemEvent.create)
          .firstWhere((event) {
            if (!event.isDirectory) {
              return false;
            }
            return Directory(event.path).parent.absolute.path ==
                backupsDirectory.absolute.path;
          })
          .then((event) => event.path.split(Platform.pathSeparator).last);

      final resultFuture = fixture.service.createBackup();
      final firstDirectoryName = await firstPublishedDirectory.timeout(
        const Duration(seconds: 5),
      );
      final result = await resultFuture;

      expect(firstDirectoryName, startsWith('.pending-'));
      expect(result.directory.path, isNot(contains('.pending-')));
      expect(await fixture.service.validateBackup(result.directory), isNotNull);
      expect(
        await result.directory.parent
            .list()
            .where((entry) => entry.path.contains('.pending-'))
            .isEmpty,
        isTrue,
      );
    });

    test(
      'publishes concurrent same-clock backups without sharing pending data',
      () async {
        final fixture = await _BackupFixture.create(
          timestamp: DateTime(2026, 8, 9, 10),
        );
        addTearDown(fixture.dispose);
        await fixture.writeDatabaseValue('concurrent');

        final results = await Future.wait([
          fixture.service.createBackup(purpose: BackupPurpose.manual),
          fixture.service.createBackup(purpose: BackupPurpose.migration),
        ]);

        expect(
          results.map((result) => result.directory.path).toSet(),
          hasLength(2),
        );
        expect(results.map((result) => result.purpose).toSet(), {
          BackupPurpose.manual,
          BackupPurpose.migration,
        });
        for (final result in results) {
          final validated = await fixture.service.validateBackup(
            result.directory,
          );
          expect(validated.purpose, result.purpose);
        }
        final backupsDirectory = await fixture.workspaceService
            .resolveBackupsDirectory();
        expect(
          await backupsDirectory
              .list()
              .where((entry) => entry.path.contains('.pending-'))
              .isEmpty,
          isTrue,
        );
      },
    );

    test('writes correct manifest content', () async {
      final fixture = await _BackupFixture.create(
        timestamp: DateTime(2026, 5, 13, 9, 10, 11),
      );
      addTearDown(fixture.dispose);
      await fixture.writeDatabaseValue('manifest-check');
      await fixture.workspaceService.saveWeeklyPromptTemplate('template');
      await fixture.writeLocalLibraryFile(
        'library_manifest.json',
        '{"documents":[{"id":"doc_manifest","isDeleted":true}]}',
      );

      final result = await fixture.service.createBackup();
      final manifestFile = File(
        '${result.directory.path}${Platform.pathSeparator}backup_manifest.json',
      );
      final manifest = BackupManifest.fromJson(
        (jsonDecode(await manifestFile.readAsString()) as Map)
            .cast<String, Object?>(),
      );
      final databaseBackup = File(
        '${result.directory.path}${Platform.pathSeparator}${manifest.databaseFile.path}',
      );
      final preferencesBackup = File(
        '${result.directory.path}${Platform.pathSeparator}${manifest.preferencesFile.path}',
      );
      final localFiles = manifest.localFileLibraryFiles;

      expect(manifest.manifestVersion, BackupManifest.currentManifestVersion);
      expect(manifest.appVersion, '0.1.0+1');
      expect(manifest.createdAt, DateTime(2026, 5, 13, 9, 10, 11));
      expect(manifest.schemaVersion, AppDatabase.currentSchemaVersion);
      expect(manifest.workspacePath, fixture.workspaceDirectory.path);
      expect(manifest.databaseFile.path, 'research_life.sqlite');
      expect(manifest.databaseFile.sizeBytes, await databaseBackup.length());
      expect(manifest.databaseFile.sha256, await _sha256(databaseBackup));
      expect(manifest.preferencesFile.path, 'preferences.json');
      expect(
        manifest.preferencesFile.sizeBytes,
        await preferencesBackup.length(),
      );
      expect(manifest.preferencesFile.sha256, await _sha256(preferencesBackup));
      expect(localFiles, isNotNull);
      expect(localFiles!.map((file) => file.path), [
        'local_files/library_manifest.json',
      ]);
      final localLibraryBackup = File(
        '${result.directory.path}${Platform.pathSeparator}${localFiles.single.path.replaceAll('/', Platform.pathSeparator)}',
      );
      expect(localFiles.single.sizeBytes, await localLibraryBackup.length());
      expect(localFiles.single.sha256, await _sha256(localLibraryBackup));
    });

    test('portable backup excludes ordinary preference credentials', () async {
      final fixture = await _BackupFixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeDatabaseValue('credentials');
      await fixture.writePreference(
        'agentLlmSettings',
        '{"apiKey":"agent-secret","modelName":"model"}',
      );
      await fixture.writePreference(
        'remoteLlmAnalysisSettings',
        '{"apiKey":"analysis-secret"}',
      );
      await fixture.writePreference('weatherApiKey', 'weather-secret');
      await fixture.writePreference('colorTheme', 'green');

      final result = await fixture.service.createBackup();
      final backupDatabase = File(
        '${result.directory.path}${Platform.pathSeparator}research_life.sqlite',
      );
      final database = sqlite3.open(backupDatabase.path);
      final keys = database
          .select('SELECT "key" FROM preferences ORDER BY "key";')
          .map((row) => row['key'])
          .toList();

      expect(keys, contains('colorTheme'));
      expect(keys, isNot(contains('agentLlmSettings')));
      expect(keys, isNot(contains('remoteLlmAnalysisSettings')));
      expect(keys, isNot(contains('weatherApiKey')));
      database.close();
      final rawDatabase = String.fromCharCodes(
        await backupDatabase.readAsBytes(),
      );
      expect(rawDatabase, isNot(contains('agent-secret')));
      expect(rawDatabase, isNot(contains('analysis-secret')));
      expect(rawDatabase, isNot(contains('weather-secret')));
      final legacyPreferences = await File(
        '${result.directory.path}${Platform.pathSeparator}preferences.json',
      ).readAsString();
      expect(legacyPreferences, isNot(contains('agent-secret')));
      expect(legacyPreferences, isNot(contains('analysis-secret')));
      expect(legacyPreferences, isNot(contains('weather-secret')));
    });

    test('backup restores chat history without AI credential bytes', () async {
      const secret = 'agent-secret-never-in-backup';
      final fixture = await _BackupFixture.create();
      addTearDown(fixture.dispose);
      final credentialStore = _MemoryAiCredentialStore();
      await credentialStore.write('primary', secret);

      final sourceDatabase = AppDatabase(
        openDatabaseConnection(fixture.workspaceService),
      );
      final sourceChats = AgentChatRepository(
        sourceDatabase,
        operationCoordinator: LocalDataOperationCoordinator(),
      );
      final session = await sourceChats.createSession(
        profileId: 'primary',
        model: 'model-a',
        title: '科研问答',
      );
      await sourceChats.appendMessage(
        sessionId: session.id,
        role: 'user',
        content: '问题',
      );
      await sourceChats.appendMessage(
        sessionId: session.id,
        role: 'assistant',
        content: '回答',
        model: 'model-a',
      );
      await sourceDatabase.close();

      final result = await fixture.service.createBackup();
      final backupDatabaseFile = File(
        p.join(result.directory.path, 'research_life.sqlite'),
      );
      final backupDatabaseBytes = await backupDatabaseFile.readAsBytes();
      final backupPreferencesBytes = await File(
        p.join(result.directory.path, 'preferences.json'),
      ).readAsBytes();
      final backupManifestBytes = await File(
        p.join(result.directory.path, 'backup_manifest.json'),
      ).readAsBytes();

      for (final bytes in <List<int>>[
        backupDatabaseBytes,
        backupPreferencesBytes,
        backupManifestBytes,
      ]) {
        expect(
          latin1.decode(bytes, allowInvalid: true),
          isNot(contains(secret)),
        );
      }

      final backupDatabase = AppDatabase(NativeDatabase(backupDatabaseFile));
      final backupChats = AgentChatRepository(
        backupDatabase,
        operationCoordinator: LocalDataOperationCoordinator(),
      );
      expect((await backupChats.listSessions()).single.title, '科研问答');
      expect(
        (await backupChats.listMessages(
          session.id,
        )).map((message) => message.content),
        <String>['问题', '回答'],
      );
      await backupDatabase.close();

      final changedDatabase = AppDatabase(
        openDatabaseConnection(fixture.workspaceService),
      );
      final changedChats = AgentChatRepository(
        changedDatabase,
        operationCoordinator: LocalDataOperationCoordinator(),
      );
      await changedChats.deleteSession(session.id);
      await changedDatabase.close();

      await fixture.service.restoreBackup(result.directory);
      final restoredDatabase = AppDatabase(
        openDatabaseConnection(fixture.workspaceService),
      );
      final restoredChats = AgentChatRepository(
        restoredDatabase,
        operationCoordinator: LocalDataOperationCoordinator(),
      );
      expect(
        (await restoredChats.listMessages(
          session.id,
        )).map((message) => message.content),
        <String>['问题', '回答'],
      );
      await restoredDatabase.close();
      expect(await credentialStore.read('primary'), secret);
    });

    test(
      'sanitizes secrets actually stored in legacy preferences json',
      () async {
        final fixture = await _BackupFixture.create();
        addTearDown(fixture.dispose);
        await fixture.writeDatabaseValue('legacy-json-secrets');
        await fixture.writeLegacyPreferences(<String, Object?>{
          'agentLlmSettings': <String, Object?>{'apiKey': 'agent-json-secret'},
          'remoteLlmAnalysisSettings': <String, Object?>{
            'apiKey': 'analysis-json-secret',
          },
          'weatherApiKey': 'weather-json-secret',
          'colorTheme': 'green',
        });

        final result = await fixture.service.createBackup();
        final preferencesFile = File(
          '${result.directory.path}${Platform.pathSeparator}preferences.json',
        );
        final manifestFile = File(
          '${result.directory.path}${Platform.pathSeparator}backup_manifest.json',
        );
        final preferencesBytes = String.fromCharCodes(
          await preferencesFile.readAsBytes(),
        );
        final manifestBytes = String.fromCharCodes(
          await manifestFile.readAsBytes(),
        );
        final decoded = (jsonDecode(preferencesBytes) as Map)
            .cast<String, Object?>();

        for (final secret in const [
          'agent-json-secret',
          'analysis-json-secret',
          'weather-json-secret',
        ]) {
          expect(preferencesBytes, isNot(contains(secret)));
          expect(manifestBytes, isNot(contains(secret)));
        }
        expect(decoded, <String, Object?>{'colorTheme': 'green'});
      },
    );

    for (final invalid in <String>[
      '{"weatherApiKey":"source-secret"',
      '["source-secret"]',
    ]) {
      test(
        'rejects unsafe legacy preferences shape without publishing: $invalid',
        () async {
          final fixture = await _BackupFixture.create();
          addTearDown(fixture.dispose);
          await fixture.writeDatabaseValue('invalid-legacy-json');
          await fixture.writeRawLegacyPreferences(invalid);
          final sourceFile = await fixture.workspaceService
              .resolvePreferencesFile();
          final sourceBytes = await sourceFile.readAsBytes();

          await expectLater(
            fixture.service.createBackup(),
            throwsA(isA<BackupException>()),
          );

          expect(await sourceFile.readAsBytes(), sourceBytes);
          final backups = await fixture.workspaceService
              .resolveBackupsDirectory();
          expect(await backups.list().toList(), isEmpty);
        },
      );
    }

    test('persists backup purpose in the validated manifest', () async {
      final fixture = await _BackupFixture.create(
        timestamp: DateTime(2026, 8, 9, 10),
      );
      addTearDown(fixture.dispose);
      await fixture.writeDatabaseValue('migration-source');

      final result = await fixture.service.createBackup(
        purpose: BackupPurpose.migration,
      );
      final validated = await fixture.service.validateBackup(result.directory);

      expect(result.purpose, BackupPurpose.migration);
      expect(result.manifest.purpose, BackupPurpose.migration);
      expect(validated.purpose, BackupPurpose.migration);
      final manifestJson =
          jsonDecode(
                await File(
                  '${result.directory.path}${Platform.pathSeparator}backup_manifest.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      expect(manifestJson['purpose'], 'migration');
    });

    test('treats a legacy manifest without purpose as manual', () async {
      final fixture = await _BackupFixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeDatabaseValue('legacy');
      final result = await fixture.service.createBackup();
      final manifestFile = File(
        '${result.directory.path}${Platform.pathSeparator}backup_manifest.json',
      );
      final manifestJson =
          (jsonDecode(await manifestFile.readAsString()) as Map)
              .cast<String, Object?>()
            ..remove('purpose');
      await manifestFile.writeAsString(jsonEncode(manifestJson));

      final validated = await fixture.service.validateBackup(result.directory);

      expect(validated.purpose, BackupPurpose.manual);
    });

    test('rejects structurally malformed manifest metadata', () async {
      final fixture = await _BackupFixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeDatabaseValue('structural-validation');
      final malformedValues = <(String, Object?)>[
        ('createdAt', 'not-a-date'),
        ('appVersion', ''),
        ('appVersion', 42),
        ('manifestVersion', 1.9),
        ('schemaVersion', 0),
        ('schemaVersion', 3.9),
        ('workspacePath', ''),
        ('workspacePath', <Object?>[]),
        ('purpose', null),
        ('workspaceManifestFile', 'not-an-object'),
        ('localFileLibraryFiles', 'not-a-list'),
        ('localFileLibraryFiles', <Object?>[42]),
      ];

      for (final (field, malformedValue) in malformedValues) {
        final result = await fixture.service.createBackup();
        fixture.advance(const Duration(seconds: 1));
        final manifestFile = File(
          '${result.directory.path}${Platform.pathSeparator}backup_manifest.json',
        );
        final manifestJson =
            (jsonDecode(await manifestFile.readAsString()) as Map)
                .cast<String, Object?>();
        manifestJson[field] = malformedValue;
        await manifestFile.writeAsString(jsonEncode(manifestJson));

        await expectLater(
          fixture.service.validateBackup(result.directory),
          throwsA(isA<BackupValidationException>()),
          reason: field,
        );
      }
    });

    test('rejects fractional backup file sizes without truncation', () async {
      final fixture = await _BackupFixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeDatabaseValue('fractional-size');
      final result = await fixture.service.createBackup();
      final manifestFile = File(
        '${result.directory.path}${Platform.pathSeparator}backup_manifest.json',
      );
      final manifestJson =
          (jsonDecode(await manifestFile.readAsString()) as Map)
              .cast<String, Object?>();
      final databaseFile = (manifestJson['databaseFile'] as Map)
          .cast<String, Object?>();
      databaseFile['sizeBytes'] =
          (databaseFile['sizeBytes'] as int).toDouble() + 0.9;
      await manifestFile.writeAsString(jsonEncode(manifestJson));

      await expectLater(
        fixture.service.validateBackup(result.directory),
        throwsA(isA<BackupValidationException>()),
      );
    });

    test(
      'lists validated backups newest first and ignores other directories',
      () async {
        final fixture = await _BackupFixture.create(
          timestamp: DateTime(2026, 8, 9, 10),
        );
        addTearDown(fixture.dispose);
        await fixture.writeDatabaseValue('safe');
        final manual = await fixture.service.createBackup();
        fixture.advance(const Duration(seconds: 1));
        final safety = await fixture.service.createBackup(
          purpose: BackupPurpose.safety,
        );
        final backupsDirectory = await fixture.workspaceService
            .resolveBackupsDirectory();
        final invalid = Directory(
          '${backupsDirectory.path}${Platform.pathSeparator}invalid',
        );
        final pending = Directory(
          '${backupsDirectory.path}${Platform.pathSeparator}.pending-stale',
        );
        await invalid.create();
        await pending.create();

        final backups = await fixture.service.listBackups();

        expect(backups.map((backup) => backup.directory.path), [
          safety.directory.path,
          manual.directory.path,
        ]);
        expect(backups.map((backup) => backup.purpose), [
          BackupPurpose.safety,
          BackupPurpose.manual,
        ]);
        expect(await invalid.exists(), isTrue);
        expect(await pending.exists(), isTrue);
      },
    );

    test(
      'retention removes only validated backups older than the newest ten',
      () async {
        final fixture = await _BackupFixture.create(
          timestamp: DateTime(2026, 8, 9, 10),
        );
        addTearDown(fixture.dispose);
        await fixture.writeDatabaseValue('safe');
        final created = <BackupCreateResult>[];
        for (var index = 0; index < 12; index += 1) {
          created.add(await fixture.service.createBackup());
          fixture.advance(const Duration(seconds: 1));
        }
        final backupsDirectory = await fixture.workspaceService
            .resolveBackupsDirectory();
        final invalid = Directory(
          '${backupsDirectory.path}${Platform.pathSeparator}invalid',
        );
        final pending = Directory(
          '${backupsDirectory.path}${Platform.pathSeparator}.pending-stale',
        );
        await invalid.create();
        await pending.create();

        expect(await fixture.service.pruneBackups(keep: 10), 2);

        expect(await fixture.service.listBackups(), hasLength(10));
        expect(await created[0].directory.exists(), isFalse);
        expect(await created[1].directory.exists(), isFalse);
        expect(await created[2].directory.exists(), isTrue);
        expect(await created.last.directory.exists(), isTrue);
        expect(await invalid.exists(), isTrue);
        expect(await pending.exists(), isTrue);
      },
    );

    test('retention rejects a non-positive keep count', () async {
      final fixture = await _BackupFixture.create();
      addTearDown(fixture.dispose);

      await expectLater(
        fixture.service.pruneBackups(keep: 0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'retention can prune migration backups without deleting other purposes',
      () async {
        final fixture = await _BackupFixture.create();
        addTearDown(fixture.dispose);
        await fixture.writeDatabaseValue('purpose-filter');
        final manual = await fixture.service.createBackup();
        fixture.advance(const Duration(seconds: 1));
        final safety = await fixture.service.createBackup(
          purpose: BackupPurpose.safety,
        );
        final migrations = <BackupCreateResult>[];
        for (var index = 0; index < 3; index += 1) {
          fixture.advance(const Duration(seconds: 1));
          migrations.add(
            await fixture.service.createBackup(
              purpose: BackupPurpose.migration,
            ),
          );
        }

        expect(
          await fixture.service.pruneBackups(
            keep: 1,
            purposes: {BackupPurpose.migration},
          ),
          2,
        );

        expect(await manual.directory.exists(), isTrue);
        expect(await safety.directory.exists(), isTrue);
        expect(await migrations[0].directory.exists(), isFalse);
        expect(await migrations[1].directory.exists(), isFalse);
        expect(await migrations[2].directory.exists(), isTrue);
      },
    );

    test(
      'retention protects a newly created backup when the clock moves backward',
      () async {
        var timestamp = DateTime(2026, 8, 10, 10);
        final fixture = await _BackupFixture.create(clock: () => timestamp);
        addTearDown(fixture.dispose);
        await fixture.writeDatabaseValue('clock-rollback');
        for (var index = 0; index < 10; index += 1) {
          await fixture.service.createBackup(purpose: BackupPurpose.migration);
          timestamp = timestamp.add(const Duration(seconds: 1));
        }
        timestamp = DateTime(2026, 8, 9, 10);
        final newlyCreated = await fixture.service.createBackup(
          purpose: BackupPurpose.migration,
        );

        expect(
          await fixture.service.pruneBackups(
            keep: 10,
            purposes: {BackupPurpose.migration},
            protectedPaths: {
              p.relative(
                newlyCreated.directory.absolute.path,
                from: Directory.current.path,
              ),
            },
          ),
          1,
        );

        expect(await newlyCreated.directory.exists(), isTrue);
        expect(
          await fixture.service.validateBackup(newlyCreated.directory),
          isA<BackupManifest>(),
        );
        expect(await fixture.service.listBackups(), hasLength(10));
      },
    );

    test(
      'retention rejects more protected backups than the keep limit',
      () async {
        final fixture = await _BackupFixture.create();
        addTearDown(fixture.dispose);
        await fixture.writeDatabaseValue('protected-limit');
        final first = await fixture.service.createBackup();
        fixture.advance(const Duration(seconds: 1));
        final second = await fixture.service.createBackup();

        await expectLater(
          fixture.service.pruneBackups(
            keep: 1,
            protectedPaths: {
              first.directory.absolute.path,
              second.directory.absolute.path,
            },
          ),
          throwsA(isA<ArgumentError>()),
        );

        expect(await first.directory.exists(), isTrue);
        expect(await second.directory.exists(), isTrue);
      },
    );

    test('retention preserves a structurally invalid backup directory', () async {
      final fixture = await _BackupFixture.create(
        timestamp: DateTime(2026, 8, 9, 10),
      );
      addTearDown(fixture.dispose);
      await fixture.writeDatabaseValue('safe');
      final created = <BackupCreateResult>[];
      for (var index = 0; index < 12; index += 1) {
        created.add(await fixture.service.createBackup());
        fixture.advance(const Duration(seconds: 1));
      }
      final corruptDirectory = created.first.directory;
      final manifestFile = File(
        '${corruptDirectory.path}${Platform.pathSeparator}backup_manifest.json',
      );
      final manifestJson =
          (jsonDecode(await manifestFile.readAsString()) as Map)
              .cast<String, Object?>();
      manifestJson['appVersion'] = 42;
      await manifestFile.writeAsString(jsonEncode(manifestJson));

      expect(await fixture.service.pruneBackups(keep: 10), 1);

      expect(await corruptDirectory.exists(), isTrue);
      expect(await created[1].directory.exists(), isFalse);
      expect(await created[2].directory.exists(), isTrue);
    });

    test('rejects restore when sha256 validation fails', () async {
      final fixture = await _BackupFixture.create(
        timestamp: DateTime(2026, 5, 13, 9, 10, 11),
      );
      addTearDown(fixture.dispose);
      await fixture.writeDatabaseValue('original');
      await fixture.workspaceService.saveWeeklyPromptTemplate('template');
      final result = await fixture.service.createBackup();
      await fixture.writeDatabaseValue('current');
      await File(
        '${result.directory.path}${Platform.pathSeparator}research_life.sqlite',
      ).writeAsString('tampered');

      expect(
        fixture.service.restoreBackup(result.directory),
        throwsA(isA<BackupValidationException>()),
      );
      expect(await fixture.readDatabaseValue(), 'current');
    });

    test('rejects a future schema before overwriting current files', () async {
      final fixture = await _BackupFixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeDatabaseValue('backup-version');
      final backup = await fixture.service.createBackup();
      final manifestFile = File(
        '${backup.directory.path}${Platform.pathSeparator}backup_manifest.json',
      );
      final manifestJson =
          (jsonDecode(await manifestFile.readAsString()) as Map)
              .cast<String, Object?>();
      manifestJson['schemaVersion'] = AppDatabase.currentSchemaVersion + 1;
      await manifestFile.writeAsString(jsonEncode(manifestJson));
      await fixture.writeDatabaseValue('current-version');

      await expectLater(
        fixture.service.restoreBackup(backup.directory),
        throwsA(isA<BackupValidationException>()),
      );
      expect(await fixture.readDatabaseValue(), 'current-version');
    });

    test('cleanup failure cannot roll back a committed restore', () async {
      var cleanupAttempts = 0;
      final fixture = await _BackupFixture.create(
        rollbackArtifactCleaner: (entity) async {
          cleanupAttempts += 1;
          throw FileSystemException('injected cleanup failure', entity.path);
        },
      );
      addTearDown(fixture.dispose);
      await fixture.writeDatabaseValue('backup-version');
      final backup = await fixture.service.createBackup();
      await fixture.writeDatabaseValue('current-version');

      final restore = await fixture.service.restoreBackup(backup.directory);

      expect(await fixture.readDatabaseValue(), 'backup-version');
      expect(cleanupAttempts, greaterThan(0));
      expect(restore.restoredBackupDirectory.path, backup.directory.path);
    });

    test('move-aside failure preserves every current workspace byte', () async {
      final fixture = await _BackupFixture.create(
        beforeMoveAside: (entity) async {
          if (entity.path.endsWith('preferences.json')) {
            throw FileSystemException('injected move failure', entity.path);
          }
        },
      );
      addTearDown(fixture.dispose);
      await fixture.writeDatabaseValue('backup-version');
      await fixture.workspaceService.saveWeeklyPromptTemplate(
        'backup-template',
      );
      await fixture.writeLocalLibraryFile(
        'library_manifest.json',
        '{"documents":[{"id":"backup_doc","isDeleted":true}]}',
      );
      final backup = await fixture.service.createBackup();

      await fixture.writeDatabaseValue('current-version');
      await fixture.workspaceService.saveWeeklyPromptTemplate(
        'current-template',
      );
      await fixture.writeLocalLibraryFile(
        'library_manifest.json',
        '{"documents":[{"id":"current_doc","isDeleted":true}]}',
      );

      await expectLater(
        fixture.service.restoreBackup(backup.directory),
        throwsA(isA<BackupRestoreException>()),
      );

      expect(await fixture.readDatabaseValue(), 'current-version');
      expect(
        await fixture.workspaceService.loadWeeklyPromptTemplate(),
        'current-template',
      );
      expect(
        await fixture.readLocalLibraryFile('library_manifest.json'),
        '{"documents":[{"id":"current_doc","isDeleted":true}]}',
      );
    });

    test('rollback continues after one cleanup step fails', () async {
      final fixture = await _BackupFixture.create(
        beforeRestoreCopy: (source, target) async {
          if (target.path.endsWith('preferences.json')) {
            throw FileSystemException('injected copy failure', target.path);
          }
        },
        rollbackTargetCleaner: (target) async {
          if (target.path.endsWith('research_life.sqlite')) {
            throw FileSystemException(
              'injected rollback cleanup failure',
              target.path,
            );
          }
          if (await target.exists()) {
            await target.delete();
          }
        },
      );
      addTearDown(fixture.dispose);
      await fixture.writeDatabaseValue('backup-version');
      await fixture.workspaceService.saveWeeklyPromptTemplate(
        'backup-template',
      );
      await fixture.writeLocalLibraryFile(
        'library_manifest.json',
        '{"documents":[{"id":"backup_doc","isDeleted":true}]}',
      );
      final backup = await fixture.service.createBackup();

      await fixture.writeDatabaseValue('current-version');
      await fixture.workspaceService.saveWeeklyPromptTemplate(
        'current-template',
      );
      await fixture.writeLocalLibraryFile(
        'library_manifest.json',
        '{"documents":[{"id":"current_doc","isDeleted":true}]}',
      );

      await expectLater(
        fixture.service.restoreBackup(backup.directory),
        throwsA(
          isA<BackupRestoreException>().having(
            (error) => '$error',
            'message',
            contains('部分回滚失败'),
          ),
        ),
      );

      expect(
        await fixture.workspaceService.loadWeeklyPromptTemplate(),
        'current-template',
      );
      expect(
        await fixture.readLocalLibraryFile('library_manifest.json'),
        '{"documents":[{"id":"current_doc","isDeleted":true}]}',
      );
      expect(await fixture.readDatabaseValue(), 'current-version');
    });

    test('creates safety backup before restore', () async {
      var timestamp = DateTime(2026, 5, 13, 9, 10, 11);
      final fixture = await _BackupFixture.create(clock: () => timestamp);
      addTearDown(fixture.dispose);
      await fixture.writeDatabaseValue('backup-version');
      await fixture.workspaceService.saveWeeklyPromptTemplate(
        'backup-template',
      );
      final backup = await fixture.service.createBackup();

      await fixture.writeDatabaseValue('current-version');
      await fixture.workspaceService.saveWeeklyPromptTemplate(
        'current-template',
      );
      timestamp = DateTime(2026, 5, 13, 9, 11, 12);

      final restore = await fixture.service.restoreBackup(backup.directory);

      expect(await fixture.readDatabaseValue(), 'backup-version');
      expect(await restore.safetyBackup.directory.exists(), isTrue);
      expect(
        restore.safetyBackup.directory.path,
        endsWith(
          '${Platform.pathSeparator}.research_life'
          '${Platform.pathSeparator}backups'
          '${Platform.pathSeparator}2026-05-13_091112',
        ),
      );
      final safetyDatabase = File(
        '${restore.safetyBackup.directory.path}${Platform.pathSeparator}research_life.sqlite',
      );
      expect(_readDatabaseValue(safetyDatabase), 'current-version');
    });

    test('restore retains only the newest ten safety backups', () async {
      final fixture = await _BackupFixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeDatabaseValue('restore-source');
      final restoreSource = await fixture.service.createBackup();
      for (var index = 0; index < 11; index += 1) {
        fixture.advance(const Duration(seconds: 1));
        await fixture.writeDatabaseValue('safety-$index');
        await fixture.service.createBackup(purpose: BackupPurpose.safety);
      }
      fixture.advance(const Duration(seconds: 1));
      await fixture.writeDatabaseValue('current');

      await fixture.service.restoreBackup(restoreSource.directory);

      final safetyBackups = (await fixture.service.listBackups())
          .where((backup) => backup.purpose == BackupPurpose.safety)
          .toList();
      expect(safetyBackups, hasLength(10));
      expect(await restoreSource.directory.exists(), isTrue);
    });

    test('restores local PDF library files', () async {
      var timestamp = DateTime(2026, 5, 13, 9, 10, 11);
      final fixture = await _BackupFixture.create(clock: () => timestamp);
      addTearDown(fixture.dispose);
      await fixture.writeDatabaseValue('backup-version');
      await fixture.workspaceService.saveWeeklyPromptTemplate('template');
      await fixture.writeLocalLibraryFile(
        'library_manifest.json',
        '{"documents":[{"id":"backup_doc","isDeleted":true}]}',
      );
      await fixture.writeLocalLibraryFile(
        'annotations.json',
        '{"items":[{"id":"backup_annotation"}]}',
      );
      final backup = await fixture.service.createBackup();

      await fixture.writeDatabaseValue('current-version');
      await fixture.writeLocalLibraryFile(
        'library_manifest.json',
        '{"documents":[{"id":"current_doc","isDeleted":true}]}',
      );
      await fixture.writeLocalLibraryFile(
        'annotations.json',
        '{"items":[{"id":"current_annotation"}]}',
      );
      timestamp = DateTime(2026, 5, 13, 9, 11, 12);

      final restore = await fixture.service.restoreBackup(backup.directory);

      expect(await fixture.readDatabaseValue(), 'backup-version');
      expect(
        await fixture.readLocalLibraryFile('library_manifest.json'),
        '{"documents":[{"id":"backup_doc","isDeleted":true}]}',
      );
      expect(
        await fixture.readLocalLibraryFile('annotations.json'),
        '{"items":[{"id":"backup_annotation"}]}',
      );
      final safetyLibraryManifest = File(
        '${restore.safetyBackup.directory.path}${Platform.pathSeparator}local_files'
        '${Platform.pathSeparator}library_manifest.json',
      );
      expect(
        await safetyLibraryManifest.readAsString(),
        contains('current_doc'),
      );
    });
  });
}

class _BackupFixture {
  _BackupFixture({
    required this.tempDirectory,
    required this.workspaceService,
    required this.service,
    required this.workspaceDirectory,
    required _MutableClock mutableClock,
  }) : _mutableClock = mutableClock;

  final Directory tempDirectory;
  final LocalWorkspaceService workspaceService;
  final BackupService service;
  final Directory workspaceDirectory;
  final _MutableClock _mutableClock;

  static Future<_BackupFixture> create({
    DateTime? timestamp,
    DateTime Function()? clock,
    Future<void> Function(FileSystemEntity entity)? rollbackArtifactCleaner,
    Future<void> Function(FileSystemEntity entity)? beforeMoveAside,
    Future<void> Function(File source, File target)? beforeRestoreCopy,
    Future<void> Function(File target)? rollbackTargetCleaner,
  }) async {
    final mutableClock = _MutableClock(
      timestamp ?? DateTime(2026, 5, 13, 9, 10, 11),
    );
    final tempDirectory = await Directory.systemTemp.createTemp(
      'research_life_backup_service_test',
    );
    final workspaceService = LocalWorkspaceService(
      storageDirectoryResolver: () async => tempDirectory,
    );
    final workspaceDirectory = await workspaceService.resolveStorageDirectory();
    final service = BackupService(
      workspaceService: workspaceService,
      clock: clock ?? mutableClock.call,
      rollbackArtifactCleaner: rollbackArtifactCleaner,
      beforeMoveAside: beforeMoveAside,
      beforeRestoreCopy: beforeRestoreCopy,
      rollbackTargetCleaner: rollbackTargetCleaner,
    );
    return _BackupFixture(
      tempDirectory: tempDirectory,
      workspaceService: workspaceService,
      service: service,
      workspaceDirectory: workspaceDirectory,
      mutableClock: mutableClock,
    );
  }

  void advance(Duration duration) => _mutableClock.advance(duration);

  Future<void> writeDatabaseValue(String value) async {
    final databaseFile = await workspaceService.resolveDatabaseFile();
    await databaseFile.parent.create(recursive: true);
    final database = sqlite3.open(databaseFile.path);
    try {
      database
        ..execute('CREATE TABLE IF NOT EXISTS notes (value TEXT NOT NULL);')
        ..execute('DELETE FROM notes;')
        ..execute('INSERT INTO notes (value) VALUES (?);', [value])
        ..execute('PRAGMA user_version = ${AppDatabase.currentSchemaVersion};')
        ..execute('PRAGMA wal_checkpoint(TRUNCATE);');
    } finally {
      database.close();
    }
  }

  Future<void> writePreference(String key, String value) async {
    final databaseFile = await workspaceService.resolveDatabaseFile();
    final database = sqlite3.open(databaseFile.path);
    try {
      database.execute(
        'CREATE TABLE IF NOT EXISTS preferences ('
        '"key" TEXT NOT NULL PRIMARY KEY, '
        '"value" TEXT NOT NULL, '
        '"updated_at" INTEGER NOT NULL);',
      );
      database.execute(
        'INSERT OR REPLACE INTO preferences '
        '("key", "value", "updated_at") VALUES (?, ?, ?);',
        [key, value, DateTime.now().millisecondsSinceEpoch],
      );
      database.execute('PRAGMA wal_checkpoint(TRUNCATE);');
    } finally {
      database.close();
    }
  }

  Future<void> writeLegacyPreferences(Map<String, Object?> values) async {
    await writeRawLegacyPreferences(jsonEncode(values));
  }

  Future<void> writeRawLegacyPreferences(String contents) async {
    final preferencesFile = await workspaceService.resolvePreferencesFile();
    await preferencesFile.parent.create(recursive: true);
    await preferencesFile.writeAsString(contents);
  }

  Future<String> readDatabaseValue() async {
    final databaseFile = await workspaceService.resolveDatabaseFile();
    return _readDatabaseValue(databaseFile);
  }

  Future<void> writeLocalLibraryFile(String fileName, String content) async {
    final directory = await workspaceService.resolveLocalFileLibraryDirectory();
    await File(
      '${directory.path}${Platform.pathSeparator}$fileName',
    ).writeAsString(content);
  }

  Future<String> readLocalLibraryFile(String fileName) async {
    final directory = await workspaceService.resolveLocalFileLibraryDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}$fileName',
    ).readAsString();
  }

  Future<void> dispose() {
    return tempDirectory.delete(recursive: true);
  }
}

class _MutableClock {
  _MutableClock(this.value);

  DateTime value;

  DateTime call() => value;

  void advance(Duration duration) {
    value = value.add(duration);
  }
}

String _readDatabaseValue(File databaseFile) {
  final database = sqlite3.open(databaseFile.path);
  try {
    final result = database.select('SELECT value FROM notes LIMIT 1;');
    return result.first['value'] as String;
  } finally {
    database.close();
  }
}

Future<String> _sha256(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}

final class _MemoryAiCredentialStore implements AiCredentialStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String profileId) async {
    _values.remove(profileId);
  }

  @override
  Future<bool> has(String profileId) async => _values.containsKey(profileId);

  @override
  Future<String?> read(String profileId) async => _values[profileId];

  @override
  Future<void> write(String profileId, String secret) async {
    _values[profileId] = secret;
  }
}
