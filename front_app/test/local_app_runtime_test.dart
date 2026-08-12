import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/app/local_app_runtime.dart';
import 'package:research_life/app/research_life_app.dart';
import 'package:research_life/features/auth/login_page.dart';
import 'package:research_life/services/agent/agent_models.dart';
import 'package:research_life/services/agent/ai_credential_store.dart';
import 'package:research_life/services/agent/ai_profile.dart';
import 'package:research_life/services/agent/ai_profile_repository.dart';
import 'package:research_life/services/agent/ai_runtime_services.dart';
import 'package:research_life/services/agent/openai_compatible_chat_client.dart';
import 'package:research_life/services/database/app_database.dart';
import 'package:research_life/services/database/database_connection.dart';
import 'package:research_life/services/database/repositories/agent_chat_repository.dart';
import 'package:research_life/services/database/repositories/preferences_repository.dart';
import 'package:research_life/services/storage/backup_manifest.dart';
import 'package:research_life/services/storage/backup_service.dart';
import 'package:research_life/services/storage/local_workspace_service.dart';
import 'package:research_life/services/tray/tray_service.dart';
import 'package:research_life/state/local_backup_controller.dart';
import 'package:research_life/state/research_life_controller.dart';

void main() {
  testWidgets('shows a local startup surface while opening', (tester) async {
    final gate = Completer<AppRuntime>();

    await tester.pumpWidget(
      ResearchLifeApp(runtimeFactory: (_) => gate.future),
    );

    expect(find.text('正在打开本地工作台'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('starts the local shell without an auth gate', (tester) async {
    final runtime = _FakeAppRuntime('local-shell');
    final gate = Completer<AppRuntime>();

    await tester.pumpWidget(
      ResearchLifeApp(
        runtimeFactory: (_) => gate.future,
        runtimeContentBuilder: (_, _) => const Directionality(
          textDirection: TextDirection.ltr,
          child: _TestLocalShell(),
        ),
      ),
    );
    gate.complete(runtime);
    await tester.pump();

    expect(find.byType(_TestLocalShell), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('restore closes the old runtime and installs a fresh one', (
    tester,
  ) async {
    final oldRuntime = _FakeAppRuntime('old');
    final newRuntime = _FakeAppRuntime('new');
    final runtimes = <_FakeAppRuntime>[oldRuntime, newRuntime];
    late RuntimeRestore restoreRuntime;
    var openCount = 0;

    await tester.pumpWidget(
      ResearchLifeApp(
        runtimeFactory: (restore) async {
          restoreRuntime = restore;
          return runtimes[openCount++];
        },
        runtimeContentBuilder: (_, runtime) => Directionality(
          textDirection: TextDirection.ltr,
          child: Text((runtime as _FakeAppRuntime).label),
        ),
      ),
    );
    await tester.pump();

    final restored = restoreRuntime(Directory('C:\\backups\\selected'));
    await restored;
    await tester.pump();

    expect(oldRuntime.events, ['flush', 'close', 'restore']);
    expect(openCount, 2);
    expect(find.text('new'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('failed restore reopens the local runtime', (tester) async {
    final oldRuntime = _FakeAppRuntime('old')..failRestore = true;
    final recoveryRuntime = _FakeAppRuntime('recovery');
    final runtimes = <_FakeAppRuntime>[oldRuntime, recoveryRuntime];
    late RuntimeRestore restoreRuntime;
    var openCount = 0;

    await tester.pumpWidget(
      ResearchLifeApp(
        runtimeFactory: (restore) async {
          restoreRuntime = restore;
          return runtimes[openCount++];
        },
        runtimeContentBuilder: (_, runtime) => Directionality(
          textDirection: TextDirection.ltr,
          child: Text((runtime as _FakeAppRuntime).label),
        ),
      ),
    );
    await tester.pump();

    await expectLater(
      restoreRuntime(Directory('C:\\backups\\broken')),
      throwsA(isA<BackupRestoreException>()),
    );
    await tester.pump();

    expect(oldRuntime.events, ['flush', 'close', 'restore']);
    expect(openCount, 2);
    expect(find.text('recovery'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('restore close failure reopens runtime and preserves the error', (
    tester,
  ) async {
    final oldRuntime = _FakeAppRuntime('old')..failClose = true;
    final recoveryRuntime = _FakeAppRuntime('recovery');
    final runtimes = <_FakeAppRuntime>[oldRuntime, recoveryRuntime];
    late RuntimeRestore restoreRuntime;
    var openCount = 0;

    await tester.pumpWidget(
      ResearchLifeApp(
        runtimeFactory: (restore) async {
          restoreRuntime = restore;
          return runtimes[openCount++];
        },
        runtimeContentBuilder: (_, runtime) => Directionality(
          textDirection: TextDirection.ltr,
          child: Text((runtime as _FakeAppRuntime).label),
        ),
      ),
    );
    await tester.pump();

    await expectLater(
      restoreRuntime(Directory('C:\\backups\\selected')),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'close failed after cleanup',
        ),
      ),
    );
    await tester.pump();

    expect(oldRuntime.events, ['flush', 'close']);
    expect(openCount, 2);
    expect(find.text('recovery'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('pre-close flush failure keeps the old runtime installed', (
    tester,
  ) async {
    final oldRuntime = _FakeAppRuntime('old')..failFlush = true;
    final recoveryRuntime = _FakeAppRuntime('unexpected-recovery');
    final runtimes = <_FakeAppRuntime>[oldRuntime, recoveryRuntime];
    late RuntimeRestore restoreRuntime;
    var openCount = 0;

    await tester.pumpWidget(
      ResearchLifeApp(
        runtimeFactory: (restore) async {
          restoreRuntime = restore;
          return runtimes[openCount++];
        },
        runtimeContentBuilder: (_, runtime) => Directionality(
          textDirection: TextDirection.ltr,
          child: Text((runtime as _FakeAppRuntime).label),
        ),
      ),
    );
    await tester.pump();

    await expectLater(
      restoreRuntime(Directory('C:\\backups\\selected')),
      throwsA(isA<StateError>()),
    );
    await tester.pump();

    expect(openCount, 1);
    expect(oldRuntime.closed, isFalse);
    expect(find.text('old'), findsOneWidget);

    oldRuntime.failFlush = false;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('exit during startup closes the runtime produced afterward', (
    tester,
  ) async {
    final runtime = _FakeAppRuntime('late-startup');
    final gate = Completer<AppRuntime>();

    await tester.pumpWidget(
      ResearchLifeApp(
        runtimeFactory: (_) => gate.future,
        runtimeContentBuilder: (_, _) => const SizedBox.shrink(),
      ),
    );

    var closeRequestCompleted = false;
    final closeRequest = _requestFrameworkExit(
      tester,
    ).whenComplete(() => closeRequestCompleted = true);
    await tester.pump();
    expect(closeRequestCompleted, isFalse);

    gate.complete(runtime);
    await closeRequest;
    await tester.pump();

    expect(runtime.closeCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('exit during restore closes the replacement runtime', (
    tester,
  ) async {
    final oldRuntime = _FakeAppRuntime('old')..restoreGate = Completer<void>();
    final replacement = _FakeAppRuntime('replacement');
    final runtimes = <_FakeAppRuntime>[oldRuntime, replacement];
    late RuntimeRestore restoreRuntime;
    var openCount = 0;

    await tester.pumpWidget(
      ResearchLifeApp(
        runtimeFactory: (restore) async {
          restoreRuntime = restore;
          return runtimes[openCount++];
        },
        runtimeContentBuilder: (_, runtime) => Directionality(
          textDirection: TextDirection.ltr,
          child: Text((runtime as _FakeAppRuntime).label),
        ),
      ),
    );
    await tester.pump();

    final restore = restoreRuntime(Directory('C:\\backups\\selected'));
    await tester.pump();
    var closeRequestCompleted = false;
    final closeRequest = _requestFrameworkExit(
      tester,
    ).whenComplete(() => closeRequestCompleted = true);
    await tester.pump();
    expect(closeRequestCompleted, isFalse);

    oldRuntime.restoreGate!.complete();
    await restore;
    await closeRequest;
    await tester.pump();

    expect(oldRuntime.closeCount, 1);
    expect(replacement.closeCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'terminal cleanup failure still completes a framework exit exactly once',
    (tester) async {
      final runtime = _FakeAppRuntime('cleanup-failure')..failClose = true;

      await tester.pumpWidget(
        ResearchLifeApp(
          runtimeFactory: (_) async => runtime,
          runtimeContentBuilder: (_, _) => const SizedBox.shrink(),
        ),
      );
      await tester.pump();

      final response = await _requestFrameworkExit(tester);

      expect(response, AppExitResponse.exit);
      expect(runtime.closeCount, 1);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(runtime.closeCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('native close can hide without disposing the local runtime', (
    tester,
  ) async {
    final runtime = _FakeAppRuntime('hide-on-close')..nativeCloseHandled = true;

    await tester.pumpWidget(
      ResearchLifeApp(
        runtimeFactory: (_) async => runtime,
        runtimeContentBuilder: (_, _) => const SizedBox.shrink(),
      ),
    );
    await tester.pump();

    final shouldClose = await _requestNativeClose(tester);

    expect(shouldClose, isFalse);
    expect(runtime.events, ['window-close']);
    expect(runtime.closeCount, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('native close awaits cleanup before confirming window close', (
    tester,
  ) async {
    final runtime = _FakeAppRuntime('exit-on-close');

    await tester.pumpWidget(
      ResearchLifeApp(
        runtimeFactory: (_) async => runtime,
        runtimeContentBuilder: (_, _) => const SizedBox.shrink(),
      ),
    );
    await tester.pump();

    final shouldClose = await _requestNativeClose(tester);

    expect(shouldClose, isTrue);
    expect(runtime.events, ['window-close', 'close']);
    expect(runtime.closeCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  test('Windows runner owns hide-or-confirm close without plugin re-entry', () {
    final source = File('windows/runner/flutter_window.cpp').readAsStringSync();

    expect(source, contains('HandleTopLevelWindowProc'));
    expect(source, contains('RequestDartClose'));
    expect(source, contains('if (message == WM_CLOSE)'));
    expect(source, contains('if (close_confirmed_)'));
    expect(
      source,
      contains(
        'return Win32Window::MessageHandler(hwnd, message, wparam, lparam);',
      ),
    );
  });

  test('production runtime source excludes cloud constructors', () {
    final runtimeSource = File(
      'lib/app/local_app_runtime.dart',
    ).readAsStringSync();
    final appSource = File('lib/app/research_life_app.dart').readAsStringSync();

    expect(runtimeSource, isNot(contains('AuthController(')));
    expect(runtimeSource, isNot(contains('SyncOutboxRepository(')));
    expect(runtimeSource, isNot(contains('CloudFileService(')));
    expect(runtimeSource, isNot(contains('FileSyncEngine(')));
    expect(appSource, isNot(contains('AuthScope(')));
    expect(appSource, isNot(contains('AuthGate(')));
    expect(appSource, contains('PinLockGate(child: WorkbenchShell())'));
    expect(appSource, isNot(contains("import 'app_shell.dart';")));
    expect(File('lib/app/app_shell.dart').existsSync(), isFalse);
    expect(File('lib/app/auth_gate.dart').existsSync(), isFalse);
  });

  test(
    'production local runtime opens and closes in an isolated workspace',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'research_life_local_runtime_test',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final runtime = await LocalAppRuntime.open(
        workspaceService: LocalWorkspaceService(
          storageDirectoryResolver: () async => tempDirectory,
        ),
        restoreRuntime: (_) => throw UnimplementedError(),
        requestExit: () async {},
        initializeTray: false,
      );

      expect(runtime.backupController.backups, isNotEmpty);
      expect(
        runtime.backupController.backups.first.purpose,
        BackupPurpose.migration,
      );

      await runtime.close();
      await runtime.close();
    },
  );

  test(
    'runtime opens with remote AI metadata without touching the network',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'research_life_ai_runtime_test',
      );
      addTearDown(() async {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      final workspace = LocalWorkspaceService(
        storageDirectoryResolver: () async => tempDirectory,
      );
      final seedDatabase = AppDatabase(openDatabaseConnection(workspace));
      await AiProfileRepository(PreferencesRepository(seedDatabase)).saveActive(
        AiProviderProfile(
          id: 'remote-profile',
          provider: 'deepseek',
          displayName: 'DeepSeek',
          baseUrl: 'https://api.deepseek.com/v1',
          model: 'deepseek-chat',
          requiresCredential: true,
        ),
      );
      await seedDatabase.close();
      final blockingClient = _RecordingAiChatClient();

      final runtime = await LocalAppRuntime.open(
        workspaceService: workspace,
        restoreRuntime: (_) => throw UnimplementedError(),
        requestExit: () async {},
        initializeTray: false,
        aiChatClient: blockingClient,
      );
      addTearDown(runtime.close);

      expect(runtime.aiServices, isNotNull);
      expect(blockingClient.calls, 0);
    },
  );

  test('legacy file migration completes before the migration backup', () async {
    final root = await Directory.systemTemp.createTemp(
      'research_life_runtime_legacy_migration',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final workspace = LocalWorkspaceService(
      storageDirectoryResolver: () async => root,
    );
    final legacy = File('${root.path}${Platform.pathSeparator}legacy.md');
    await legacy.writeAsString('legacy payload');
    final library = await workspace.resolveLocalFileLibraryDirectory();
    await File(
      '${library.path}${Platform.pathSeparator}library_manifest.json',
    ).writeAsString(
      jsonEncode({
        'version': 1,
        'documents': [
          {
            'id': 'legacy-doc',
            'title': 'legacy',
            'path': legacy.path,
            'fileKind': 'text',
            'category': '未分类',
            'createdAt': DateTime(2026, 1, 1).millisecondsSinceEpoch,
            'updatedAt': DateTime(2026, 1, 1).millisecondsSinceEpoch,
          },
        ],
      }),
    );

    final runtime = await LocalAppRuntime.open(
      workspaceService: workspace,
      restoreRuntime: (_) => throw UnimplementedError(),
      requestExit: () async {},
      initializeTray: false,
    );
    addTearDown(runtime.close);

    final migrated = runtime.controller.pdfDocumentById('legacy-doc')!;
    expect(migrated.path.replaceAll('\\', '/'), contains('/payloads/'));
    expect(await File(migrated.path).readAsString(), 'legacy payload');
    final migrationBackup = runtime.backupController.backups.firstWhere(
      (backup) => backup.purpose == BackupPurpose.migration,
    );
    final backedPayloads = migrationBackup.manifest.localFileLibraryFiles!
        .map((info) => info.path)
        .where((path) => path.startsWith('local_files/payloads/'));
    expect(backedPayloads, isNotEmpty);
  });

  test('tray quit paths delegate to the graceful exit coordinator', () async {
    var exitRequests = 0;
    final trayMenu = TrayService(
      controller: _TrayTestController(),
      requestExit: () async => exitRequests += 1,
    );
    final windowClose = TrayService(
      controller: _TrayTestController(),
      requestExit: () async => exitRequests += 1,
    );

    await trayMenu.quit();
    await windowClose.handleWindowClose();

    expect(exitRequests, 2);
  });

  test(
    'runtime disposal continues after failure and runs exactly once',
    () async {
      final events = <String>[];
      final coordinator = RuntimeDisposalCoordinator(
        prepareController: () async => events.add('prepare'),
        flushPersistence: () async {
          events.add('flush');
          throw StateError('flush failed');
        },
        waitForTrayInitialization: () async => events.add('tray-init'),
        disposeTray: () async => events.add('tray-dispose'),
        disposeBackupController: () => events.add('backup-dispose'),
        disposeController: () => events.add('controller-dispose'),
        closeDatabase: () async => events.add('database-close'),
      );

      await expectLater(coordinator.close(), throwsA(isA<StateError>()));
      await expectLater(coordinator.close(), throwsA(isA<StateError>()));

      expect(events, [
        'prepare',
        'flush',
        'tray-init',
        'tray-dispose',
        'backup-dispose',
        'controller-dispose',
        'database-close',
      ]);
    },
  );
}

class _FakeAppRuntime extends Fake implements AppRuntime {
  _FakeAppRuntime(this.label);

  final String label;
  @override
  final AiRuntimeServices aiServices = _fakeAiServices();
  final List<String> events = [];
  bool closed = false;
  int closeCount = 0;
  bool failFlush = false;
  bool failRestore = false;
  bool failClose = false;
  bool nativeCloseHandled = false;
  Completer<void>? restoreGate;

  @override
  Future<bool> handleWindowCloseRequest() async {
    events.add('window-close');
    return nativeCloseHandled;
  }

  @override
  Future<void> flushLocalPersistence() async {
    events.add('flush');
    if (failFlush) {
      throw StateError('flush failed');
    }
  }

  @override
  Future<BackupRestoreResult> restoreBackup(Directory backupDirectory) async {
    events.add('restore');
    await restoreGate?.future;
    if (failRestore) {
      throw const BackupRestoreException('restore failed');
    }
    return _FakeBackupRestoreResult();
  }

  @override
  Future<void> close() async {
    if (closed) {
      return;
    }
    closed = true;
    closeCount += 1;
    events.add('close');
    if (failClose) {
      throw StateError('close failed after cleanup');
    }
  }
}

class _FakeBackupRestoreResult extends Fake implements BackupRestoreResult {}

class _RecordingAiChatClient extends OpenAiCompatibleChatClient {
  var calls = 0;

  @override
  Future<AiChatCompletion> complete({
    required AiProviderProfile profile,
    required List<AiChatTurn> messages,
    required String? credential,
    CancelToken? cancelToken,
  }) async {
    calls += 1;
    throw StateError('Unexpected AI request during runtime startup.');
  }
}

AiRuntimeServices _fakeAiServices() => AiRuntimeServices(
  profiles: _FakeAiProfileStore(),
  credentials: _FakeAiCredentialStore(),
  chats: _FakeAgentChatStore(),
  client: _RecordingAiChatClient(),
);

class _FakeAiProfileStore extends Fake implements AiProfileStore {}

class _FakeAiCredentialStore extends Fake implements AiCredentialStore {}

class _FakeAgentChatStore extends Fake implements AgentChatStore {}

class _TestLocalShell extends StatelessWidget {
  const _TestLocalShell();

  @override
  Widget build(BuildContext context) => const Text('本地工作台');
}

class _TrayTestController extends Fake implements ResearchLifeController {
  @override
  bool get closeToTray => false;
}

Future<bool> _requestNativeClose(WidgetTester tester) async {
  final response = Completer<ByteData?>();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'research_life/window_lifecycle',
    const StandardMethodCodec().encodeMethodCall(
      const MethodCall('requestClose'),
    ),
    response.complete,
  );
  final envelope = const StandardMethodCodec().decodeEnvelope(
    (await response.future)!,
  );
  return envelope! as bool;
}

Future<AppExitResponse> _requestFrameworkExit(WidgetTester tester) async {
  final response = Completer<ByteData?>();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/platform',
    const JSONMethodCodec().encodeMethodCall(
      const MethodCall('System.requestAppExit', <Object?>[
        <String, Object?>{'type': 'cancelable'},
      ]),
    ),
    response.complete,
  );
  final envelope =
      const JSONMessageCodec().decodeMessage(await response.future)!
          as List<Object?>;
  final payload = envelope.single! as Map<Object?, Object?>;
  return payload['response'] == 'exit'
      ? AppExitResponse.exit
      : AppExitResponse.cancel;
}
