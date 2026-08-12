# Local AI Research Assistant Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the unreachable `/api/v1/agent/*` backend with a usable Windows-local research chat assistant that calls user-selected OpenAI-compatible providers directly, stores chat history locally, and keeps credentials out of databases and backups.

**Architecture:** `LocalAppRuntime` owns a small `AiRuntimeServices` bundle containing a local profile repository, Drift chat repository, Windows credential store, and stateless OpenAI-compatible HTTP client. `AgentController` coordinates those services without using `ResearchLifeController`; `AgentPage` reads the bundle from `LocalServicesScope`, so opening the app, Research, or Agent only reads local state and never starts a network request.

**Tech Stack:** Flutter 3 / Dart 3.11, Drift + SQLite, Dio 5, `win32` 6 + `ffi` 2, Flutter widget tests, loopback `HttpServer` contract tests.

## Global Constraints

- Windows single-device, local-only runtime; no login, account, cloud sync, or backend dependency.
- AI has one reachable entry: `Research → AI Assistant`; do not add it to the global sidebar or Settings.
- API credentials must exist only in Windows Credential Manager and must never enter SQLite, preferences JSON, logs, diagnostics, or backup artifacts.
- Chat sessions and messages are local SQLite data and are included in normal validated backups.
- App startup, Research opening, Agent bootstrap, and settings opening perform no network request; network starts only after an explicit Send or Retry action.
- First release supports DeepSeek, OpenAI, Moonshot, Zhipu, Ollama, and custom OpenAI-compatible endpoints.
- Base URL and model are editable; provider presets use values verified against official provider documentation on the implementation date.
- Ollama may run without a credential; remote presets require one.
- First release is non-streaming and excludes web search, tools, RAG, automatic PDF/note context, voice, sync, and weekly-analysis AI.
- Remove the old fake Fast / Expert / Deep Thinking controls instead of implying cross-provider capabilities that do not exist.
- UI copy stays concise and uses the existing workbench tokens and selective glass styling.
- Preserve all unrelated dirty-worktree changes; stage and commit only the files listed for each task.
- Use RED → GREEN for every production behavior. Do not write production code before the named failing test has been observed.

---

## File Structure

**Create**

- `lib/services/agent/ai_profile.dart` — non-secret profile model, provider presets, validation, JSON.
- `lib/services/agent/ai_profile_repository.dart` — one active profile stored through `PreferencesRepository`.
- `lib/services/agent/ai_credential_store.dart` — credential interface and domain exception.
- `lib/services/agent/windows_ai_credential_store.dart` — Windows Credential Manager adapter.
- `lib/services/agent/openai_compatible_chat_client.dart` — URL normalization, HTTP request, response/error mapping.
- `lib/services/agent/ai_runtime_services.dart` — runtime-owned dependency bundle and controller factory.
- `lib/services/database/repositories/agent_chat_repository.dart` — local session/message persistence behind the write coordinator.
- `drift_schemas/schema_v8.json` and `drift_schemas/schema_v9.json` — migration fixtures.
- `test/generated/app_database_schema/` — generated Drift schema helper and version classes.
- `test/ai_profile_repository_test.dart`
- `test/agent_chat_repository_test.dart`
- `test/windows_ai_credential_store_test.dart`
- `test/openai_compatible_chat_client_test.dart`
- `test/agent_controller_test.dart`
- `test/agent_page_test.dart`

**Modify**

- `lib/services/database/app_database.dart` and generated `app_database.g.dart` — schema 9 tables and migration.
- `lib/services/agent/agent_models.dart` — local session/message and completion result models.
- `lib/features/agent/state/agent_controller.dart` — local-first orchestration and retry.
- `lib/features/agent/agent_page.dart` — production AI workspace and inline configuration dialog.
- `lib/app/local_app_runtime.dart` — create and expose AI services without eager network work.
- `lib/app/local_services_scope.dart` — expose `AiRuntimeServices` to Agent UI.
- `lib/app/research_life_app.dart` — pass runtime AI services into the scope.
- `lib/state/research_life_controller.dart` — remove dormant UI-facing Agent settings state and requests.
- `lib/core/models/app_models.dart` — remove obsolete `AgentLlmSettings`.
- `lib/services/database/repositories/preferences_repository.dart` — keep the legacy key constant for backup sanitization, remove unused legacy Agent load/save methods.
- `lib/services/agent/agent_api.dart` — delete after all imports are removed.
- `test/local_app_runtime_test.dart`, `test/local_only_pages_test.dart`, `test/backup_service_test.dart`, `test/workbench_workspaces_test.dart` — runtime, boundary, security, and entry regressions.

---

### Task 1: Non-secret AI profile and provider presets

**Files:**
- Create: `lib/services/agent/ai_profile.dart`
- Create: `lib/services/agent/ai_profile_repository.dart`
- Test: `test/ai_profile_repository_test.dart`
- Modify: `lib/services/database/repositories/preferences_repository.dart`

**Interfaces:**
- Produces: `AiProviderProfile`, `AiProviderPreset`, `aiProviderPresets`, `AiProfileRepository.loadActive()`, `saveActive()`, `clearActive()`.
- Consumes: existing `PreferencesRepository.loadString/saveString/deleteString`, which already participates in `LocalDataOperationCoordinator`.

- [ ] **Step 1: Write the failing profile tests**

```dart
test('profile JSON round-trip never has a credential field', () {
  const profile = AiProviderProfile(
    id: 'primary',
    provider: 'deepseek',
    displayName: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-v4-flash',
    requiresCredential: true,
  );

  final json = profile.toJson();

  expect(json.keys, isNot(contains('apiKey')));
  expect(json.keys, isNot(contains('credential')));
  expect(AiProviderProfile.fromJson(json), profile);
});

test('repository stores one active non-secret profile', () async {
  await repository.saveActive(profile);
  expect(await repository.loadActive(), profile);
  await repository.clearActive();
  expect(await repository.loadActive(), isNull);
});
```

- [ ] **Step 2: Run RED**

Run: `flutter test test/ai_profile_repository_test.dart`

Expected: compile failure because `AiProviderProfile` and `AiProfileRepository` do not exist.

- [ ] **Step 3: Implement the minimal profile API**

```dart
final class AiProviderProfile {
  const AiProviderProfile({
    required this.id,
    required this.provider,
    required this.displayName,
    required this.baseUrl,
    required this.model,
    required this.requiresCredential,
  });

  final String id;
  final String provider;
  final String displayName;
  final String baseUrl;
  final String model;
  final bool requiresCredential;

  Map<String, Object?> toJson() => {
    'id': id,
    'provider': provider,
    'displayName': displayName,
    'baseUrl': baseUrl,
    'model': model,
    'requiresCredential': requiresCredential,
  };
}
```

Implement equality/hashCode, strict trimmed validation, `fromJson`, and presets for the six approved choices. `AiProfileRepository` stores JSON under `localAiProfileV1`; it must not migrate or read `agentLlmSettings`.

- [ ] **Step 4: Verify GREEN and profile barrier behavior**

Run: `flutter test test/ai_profile_repository_test.dart test/local_data_operation_coordinator_test.dart`

Expected: all tests pass; add one test that holds a coordinator lease and proves `saveActive()` waits until release.

- [ ] **Step 5: Commit only Task 1 files**

```powershell
git add lib/services/agent/ai_profile.dart lib/services/agent/ai_profile_repository.dart lib/services/database/repositories/preferences_repository.dart test/ai_profile_repository_test.dart
git commit -m "feat: add non-secret local AI profiles"
```

---

### Task 2: Drift schema 9 and local chat repository

**Files:**
- Modify: `lib/services/database/app_database.dart`
- Modify generated: `lib/services/database/app_database.g.dart`
- Modify: `lib/services/agent/agent_models.dart`
- Create: `lib/services/database/repositories/agent_chat_repository.dart`
- Create: `drift_schemas/schema_v8.json`
- Create: `drift_schemas/schema_v9.json`
- Create generated: `test/generated/app_database_schema/`
- Create: `test/agent_chat_repository_test.dart`

**Interfaces:**
- Produces: `AgentChatRepository.createSession`, `listSessions`, `listMessages`, `appendMessage`, `updateSessionAfterReply`, `deleteSession`.
- Produces local models with integer ids: `AgentChatSession` and `AgentChatMessage`.
- Consumes: `AppDatabase` and `LocalDataOperationCoordinator`.

- [ ] **Step 1: Capture the real schema 8 fixture before changing the database**

Run:

```powershell
dart run drift_dev schema dump lib/services/database/app_database.dart drift_schemas/schema_v8.json
```

Expected: `schema_v8.json` describes the current 12 tables; its version is derived from the required `schema_v8.json` filename.

- [ ] **Step 2: Write failing repository tests**

```dart
test('creates a session and returns messages in insertion order', () async {
  final session = await repository.createSession(
    profileId: 'primary',
    model: 'model-a',
    title: '新对话',
  );
  await repository.appendMessage(
    sessionId: session.id,
    role: 'user',
    content: '问题',
  );
  await repository.appendMessage(
    sessionId: session.id,
    role: 'assistant',
    content: '回答',
    model: 'model-a',
  );

  expect((await repository.listMessages(session.id)).map((m) => m.role), [
    'user',
    'assistant',
  ]);
});

test('delete session removes its messages transactionally', () async {
  final session = await seededSession(repository);
  await repository.deleteSession(session.id);
  expect(await repository.listMessages(session.id), isEmpty);
  expect(await repository.listSessions(), isEmpty);
});
```

- [ ] **Step 3: Run RED**

Run: `flutter test test/agent_chat_repository_test.dart`

Expected: compile failure for missing tables/repository methods.

- [ ] **Step 4: Add the two tables and migration**

```dart
class AgentChatSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  TextColumn get profileId => text()();
  TextColumn get model => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
}

class AgentChatMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer().references(AgentChatSessions, #id)();
  TextColumn get role => text()();
  TextColumn get content => text()();
  TextColumn get reasoningContent => text().nullable()();
  TextColumn get model => text().nullable()();
  IntColumn get createdAt => integer()();
}
```

Set `currentSchemaVersion = 9`; register both tables; in `onUpgrade`, when `from < 9`, create sessions before messages. Repository writes must wrap the whole transaction inside one coordinator lease.

- [ ] **Step 5: Regenerate code and schema helpers**

Run:

```powershell
dart run build_runner build --delete-conflicting-outputs
dart run drift_dev schema dump lib/services/database/app_database.dart drift_schemas/schema_v9.json
dart run drift_dev schema generate drift_schemas test/generated/app_database_schema
```

Expected: generated database includes both tables; generated helper contains schema versions 8 and 9.

- [ ] **Step 6: Add and run the 8 → 9 migration verification**

```dart
test('schema 8 migrates to schema 9 without changing existing rows', () async {
  final verifier = SchemaVerifier(GeneratedHelper());
  final connection = await verifier.startAt(8);
  final db = AppDatabase(connection.executor);
  await verifier.migrateAndValidate(db, 9);
  addTearDown(db.close);
});
```

Run: `flutter test test/agent_chat_repository_test.dart`

Expected: repository, ordering, deletion, write-barrier, and schema migration tests pass.

- [ ] **Step 7: Commit only Task 2 files**

```powershell
git add lib/services/database/app_database.dart lib/services/database/app_database.g.dart lib/services/database/repositories/agent_chat_repository.dart lib/services/agent/agent_models.dart drift_schemas test/generated/app_database_schema test/agent_chat_repository_test.dart
git commit -m "feat: persist local AI conversations"
```

---

### Task 3: Windows Credential Manager boundary

**Files:**
- Create: `lib/services/agent/ai_credential_store.dart`
- Create: `lib/services/agent/windows_ai_credential_store.dart`
- Create: `test/windows_ai_credential_store_test.dart`

**Interfaces:**
- Produces: `AiCredentialStore.read(profileId)`, `write(profileId, secret)`, `delete(profileId)`, `has(profileId)`.
- Produces: `CredentialPlatformApi` for deterministic unit injection; production implementation wraps Win32.

- [ ] **Step 1: Write failing credential behavior tests against a fake platform API**

```dart
test('uses the stable app target and never exposes enumeration', () async {
  final api = RecordingCredentialPlatformApi();
  final store = WindowsAiCredentialStore(platform: api);

  await store.write('primary', 'secret-value');
  expect(api.lastTarget, 'research-life-app/ai/primary');
  expect(await store.read('primary'), 'secret-value');
  await store.delete('primary');
  expect(await store.read('primary'), isNull);
});

test('rejects blank secrets before calling Windows', () async {
  final api = RecordingCredentialPlatformApi();
  final store = WindowsAiCredentialStore(platform: api);
  await expectLater(store.write('primary', '   '), throwsArgumentError);
  expect(api.writeCount, 0);
});
```

- [ ] **Step 2: Run RED**

Run: `flutter test test/windows_ai_credential_store_test.dart`

Expected: compile failure because the store does not exist.

- [ ] **Step 3: Implement Win32 read/write/delete**

Use `CredWrite`, `CredRead`, `CredFree`, and `CredDelete` with `CRED_TYPE_GENERIC`, UTF-8 credential bytes, and `CRED_PERSIST_LOCAL_MACHINE`. Convert `ERROR_NOT_FOUND` to `null`/successful no-op delete; convert other HRESULTs to `AiCredentialException('Windows 凭据操作失败')` without including the target secret or blob.

```dart
abstract interface class AiCredentialStore {
  Future<String?> read(String profileId);
  Future<void> write(String profileId, String secret);
  Future<void> delete(String profileId);
  Future<bool> has(String profileId);
}
```

- [ ] **Step 4: Verify GREEN and source policy**

Run:

```powershell
flutter test test/windows_ai_credential_store_test.dart
rg -n "apiKey|secret-value" lib/services/agent -g "*.dart"
```

Expected: tests pass; production code contains parameter names but no literal credential and no file/preferences write path.

- [ ] **Step 5: Commit only Task 3 files**

```powershell
git add lib/services/agent/ai_credential_store.dart lib/services/agent/windows_ai_credential_store.dart test/windows_ai_credential_store_test.dart
git commit -m "feat: secure AI keys in Windows credentials"
```

---

### Task 4: Direct OpenAI-compatible HTTP client

**Files:**
- Create: `lib/services/agent/openai_compatible_chat_client.dart`
- Modify: `lib/services/agent/agent_models.dart`
- Create: `test/openai_compatible_chat_client_test.dart`

**Interfaces:**
- Produces: `OpenAiCompatibleChatClient.complete(profile:, messages:, credential:, cancelToken:)` returning `AiChatCompletion`.
- Produces: `AiChatClientException.kind` values `authentication`, `rateLimited`, `unreachable`, `timeout`, `invalidResponse`, `server`, `cancelled`.

- [ ] **Step 1: Write loopback-server contract tests**

```dart
test('posts ordered messages and bearer auth to chat completions', () async {
  final request = await recorder.nextRequest();
  expect(request.uri.path, '/v1/chat/completions');
  expect(request.headers.value('authorization'), 'Bearer test-key');
  expect(request.jsonBody['model'], 'model-a');
  expect(request.jsonBody['messages'], [
    {'role': 'user', 'content': '问题'},
  ]);
});

test('ollama sends no authorization header when key is absent', () async {
  await client.complete(
    profile: ollamaProfile,
    messages: const [AiChatTurn(role: 'user', content: 'hello')],
    credential: null,
  );
  expect(recorder.last.headers.value('authorization'), isNull);
});
```

Add separate tests for a Base URL already ending in `/v1`, a full `/chat/completions` URL, empty `choices`, 401, 429, 500, receive timeout, and Dio cancellation.

- [ ] **Step 2: Run RED**

Run: `flutter test test/openai_compatible_chat_client_test.dart`

Expected: compile failure for missing client and completion types.

- [ ] **Step 3: Implement URL normalization and one JSON request**

```dart
Future<AiChatCompletion> complete({
  required AiProviderProfile profile,
  required List<AiChatTurn> messages,
  required String? credential,
  CancelToken? cancelToken,
});
```

Rules: require absolute HTTP(S); allow HTTP for loopback/Ollama and explicit custom endpoints; append `/chat/completions` exactly once; add Bearer only for nonblank credentials; send only `model` and ordered `messages`; parse `choices[0].message.content`, optional `reasoning_content`, returned `model`, and `finish_reason`. Never attach an interceptor that logs headers or bodies.

- [ ] **Step 4: Verify GREEN**

Run: `flutter test test/openai_compatible_chat_client_test.dart`

Expected: all success/error/cancel contracts pass against the real loopback HTTP stack.

- [ ] **Step 5: Commit only Task 4 files**

```powershell
git add lib/services/agent/openai_compatible_chat_client.dart lib/services/agent/agent_models.dart test/openai_compatible_chat_client_test.dart
git commit -m "feat: call OpenAI-compatible chat providers"
```

---

### Task 5: Local-first Agent controller

**Files:**
- Modify: `lib/features/agent/state/agent_controller.dart`
- Create: `test/agent_controller_test.dart`
- Delete after GREEN: `lib/services/agent/agent_api.dart`

**Interfaces:**
- Consumes: profile repository, credential store, chat repository, HTTP client.
- Produces: `bootstrap`, `saveConfiguration`, `deleteCredential`, `startNewSession`, `openSession`, `deleteSession`, `sendMessage`, `retryFailedMessage`, `cancelActiveRequest`.

- [ ] **Step 1: Write failing controller tests**

```dart
test('bootstrap reads local state and never calls the HTTP client', () async {
  await controller.bootstrap();
  expect(client.calls, 0);
  expect(controller.profile, profile);
});

test('failed request keeps one user message and retry does not duplicate it', () async {
  client.failNext(AiChatClientException.unreachable());
  await controller.sendMessage('问题');
  expect(controller.messages.where((m) => m.isUser), hasLength(1));
  expect(controller.canRetry, isTrue);

  client.replyNext('回答');
  await controller.retryFailedMessage();
  expect(controller.messages.where((m) => m.isUser), hasLength(1));
  expect(controller.messages.where((m) => m.isAssistant), hasLength(1));
});

test('missing credential never starts a request', () async {
  await controller.sendMessage('问题');
  expect(controller.needsConfiguration, isTrue);
  expect(client.calls, 0);
});
```

Also test one in-flight send, first-message title truncation, local save failure before HTTP, assistant save failure with visible volatile answer, session deletion, and cancellation without user-facing error.

- [ ] **Step 2: Run RED**

Run: `flutter test test/agent_controller_test.dart`

Expected: constructor/API mismatch because controller still requires `AgentApi`.

- [ ] **Step 3: Replace backend orchestration**

Constructor:

```dart
AgentController({
  required AiProfileRepository profiles,
  required AiCredentialStore credentials,
  required AgentChatRepository chats,
  required OpenAiCompatibleChatClient client,
});
```

`bootstrap()` loads the active profile, credential presence, sessions, and first session messages only. `sendMessage()` follows the spec commit order: local session → local user message → local context read → HTTP → local assistant message. Track the failed user message id so Retry reuses it. `dispose()` cancels the active Dio token and performs no persistence fire-and-forget.

- [ ] **Step 4: Remove the old service client and verify GREEN**

Run:

```powershell
flutter test test/agent_controller_test.dart
rg -n "/api/v1/agent|AgentApi" lib test -g "*.dart"
```

Expected: controller tests pass and `rg` has no matches; then delete `lib/services/agent/agent_api.dart`.

- [ ] **Step 5: Commit only Task 5 files**

```powershell
git add lib/features/agent/state/agent_controller.dart lib/services/agent/agent_api.dart test/agent_controller_test.dart
git commit -m "feat: make AI conversations local first"
```

---

### Task 6: Runtime ownership and zero-startup-network wiring

**Files:**
- Create: `lib/services/agent/ai_runtime_services.dart`
- Modify: `lib/app/local_app_runtime.dart`
- Modify: `lib/app/local_services_scope.dart`
- Modify: `lib/app/research_life_app.dart`
- Modify: `test/local_app_runtime_test.dart`

**Interfaces:**
- Produces: `AppRuntime.aiServices` and `LocalServicesScope.aiServices`.
- `AiRuntimeServices.createController()` creates an Agent controller on demand; constructing the bundle performs no HTTP call.

- [ ] **Step 1: Write the failing runtime boundary test**

```dart
test('runtime opens with remote AI metadata without touching the network', () async {
  final blockingClient = RecordingAiChatClient();
  final runtime = await LocalAppRuntime.open(
    workspaceService: workspace,
    restoreRuntime: restore,
    requestExit: () async {},
    initializeTray: false,
    aiChatClient: blockingClient,
  );
  addTearDown(runtime.close);

  expect(runtime.aiServices, isNotNull);
  expect(blockingClient.calls, 0);
});
```

- [ ] **Step 2: Run RED**

Run: `flutter test test/local_app_runtime_test.dart --plain-name "runtime opens with remote AI metadata without touching the network"`

Expected: missing `aiServices` and injection argument.

- [ ] **Step 3: Build the runtime service bundle**

```dart
final class AiRuntimeServices {
  const AiRuntimeServices({
    required this.profiles,
    required this.credentials,
    required this.chats,
    required this.client,
  });

  AgentController createController() => AgentController(
    profiles: profiles,
    credentials: credentials,
    chats: chats,
    client: client,
  );
}
```

Instantiate repositories with the same `AppDatabase`, `PreferencesRepository`, and `LocalDataOperationCoordinator` already owned by `LocalAppRuntime`. Default credential store is Windows; default client is a plain Dio client with connect/receive/send timeouts. Do not call `bootstrap()` in runtime open.

- [ ] **Step 4: Pass services through the app scopes and update fake runtimes**

Add `AiRuntimeServices get aiServices` to `AppRuntime`; add a required `aiServices` field to `LocalServicesScope`; pass `runtime.aiServices` from `ResearchLifeApp`. Update `_FakeAppRuntime` and LocalServicesScope tests with deterministic fake bundles.

- [ ] **Step 5: Verify GREEN**

Run: `flutter test test/local_app_runtime_test.dart test/settings_local_backup_panel_test.dart`

Expected: runtime and scope tests pass with zero AI HTTP calls.

- [ ] **Step 6: Commit only Task 6 files**

```powershell
git add lib/services/agent/ai_runtime_services.dart lib/app/local_app_runtime.dart lib/app/local_services_scope.dart lib/app/research_life_app.dart test/local_app_runtime_test.dart test/settings_local_backup_panel_test.dart
git commit -m "feat: own local AI services in app runtime"
```

---

### Task 7: Research-only Agent workspace and secure configuration UI

**Files:**
- Modify: `lib/features/agent/agent_page.dart`
- Modify: `lib/state/research_life_controller.dart`
- Modify: `lib/core/models/app_models.dart`
- Modify: `lib/features/workbench/research_workspace.dart` only if a key/semantic label is needed.
- Create: `test/agent_page_test.dart`
- Modify: `test/workbench_workspaces_test.dart`
- Modify: `test/local_only_pages_test.dart`

**Interfaces:**
- Consumes: `LocalServicesScope.aiServices.createController()`.
- Produces widget keys: `agent-settings`, `agent-provider`, `agent-base-url`, `agent-model`, `agent-api-key`, `agent-save-settings`, `agent-delete-credential`, `agent-composer`, `agent-send`, `agent-retry`.

- [ ] **Step 1: Write failing widget tests**

```dart
testWidgets('unconfigured Agent opens its own concise settings dialog', (tester) async {
  await pumpAgent(tester, controller: unconfiguredController);
  expect(find.text('配置 AI'), findsOneWidget);
  await tester.tap(find.byKey(const Key('agent-settings')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('agent-provider')), findsOneWidget);
  expect(find.byKey(const Key('agent-api-key')), findsOneWidget);
});

testWidgets('saved key is never written back into the password field', (tester) async {
  await pumpConfiguredAgent(tester);
  await tester.tap(find.byKey(const Key('agent-settings')));
  await tester.pumpAndSettle();
  final field = tester.widget<TextField>(find.byKey(const Key('agent-api-key')));
  expect(field.controller!.text, isEmpty);
  expect(field.obscureText, isTrue);
});
```

Also cover save with blank Key retaining the credential, explicit credential delete, model chip, send/retry, local history open/delete, sidebar collapse, Markdown answer, and concise privacy copy.

- [ ] **Step 2: Run RED**

Run: `flutter test test/agent_page_test.dart test/workbench_workspaces_test.dart`

Expected: current page shows the old disabled/settings state and lacks the new keys.

- [ ] **Step 3: Rebuild AgentPage around the local controller**

Create the controller in `didChangeDependencies()` from `LocalServicesScope.read(context).aiServices`, call only local `bootstrap()`, and dispose it with the page. Keep the approved three-zone layout: collapsible 240–260 px history rail, flexible conversation surface, compact composer. Put the configuration gear in the Agent top-right, not global Settings.

Configuration behavior:

- Provider selection applies an editable official preset.
- Empty Key means keep the existing credential.
- The Key field is always blank when reopened and uses `obscureText: true`.
- Ollama labels Key “optional”.
- “删除凭据” requires a confirm dialog and does not delete chat history.
- One short disclosure states that the current conversation context is sent to the selected provider on Send.

- [ ] **Step 4: Remove the obsolete global-controller Agent state**

Delete `localAiConfigured`, `requestOpenAiSettings`, `_agentLlmSettings`, loader/saver/busy methods, and `AgentLlmSettings`. Keep `PreferencesRepository.agentLlmSettingsKey` solely for backup sanitization. Replace the old `local_only_pages_test` string assertion with these boundaries:

```dart
expect(agentPageSource, isNot(contains('ResearchLifeController')));
expect(agentPageSource, isNot(contains('/api/v1/agent')));
expect(settingsSource, isNot(contains('API Key')));
expect(researchWorkspaceSource, contains('AgentPage'));
```

- [ ] **Step 5: Verify GREEN**

Run:

```powershell
flutter test test/agent_page_test.dart test/workbench_workspaces_test.dart test/local_only_pages_test.dart
rg -n "localAiConfigured|requestOpenAiSettings|AgentLlmSettings|/api/v1/agent" lib test -g "*.dart"
```

Expected: widget/boundary tests pass and the source scan returns no obsolete runtime API.

- [ ] **Step 6: Commit only Task 7 files**

```powershell
git add lib/features/agent/agent_page.dart lib/features/workbench/research_workspace.dart lib/state/research_life_controller.dart lib/core/models/app_models.dart lib/services/database/repositories/preferences_repository.dart test/agent_page_test.dart test/workbench_workspaces_test.dart test/local_only_pages_test.dart
git commit -m "feat: deliver research-only local AI workspace"
```

---

### Task 8: Backup security, complete regression, and native Windows QA

**Files:**
- Modify: `test/backup_service_test.dart`
- Modify any production file only in response to a newly observed RED regression.
- Modify: `.superpowers/sdd/2026-08-09-workbench-ui/progress.md`

**Interfaces:**
- Verifies the complete feature; produces no new public API.

- [ ] **Step 1: Add the failing backup security/history test**

```dart
test('backup contains chat history but no AI credential bytes', () async {
  const secret = 'agent-secret-never-in-backup';
  await credentialStore.write('primary', secret);
  await seedChatHistory(database, user: '问题', assistant: '回答');

  final result = await fixture.service.createBackup();
  final databaseBytes = await File(
    p.join(result.directory.path, 'research_life.sqlite'),
  ).readAsBytes();

  expect(latin1.decode(databaseBytes, allowInvalid: true), isNot(contains(secret)));
  final restored = await openBackupDatabase(result.directory);
  expect(await restored.select(restored.agentChatMessages).get(), hasLength(2));
});
```

Retain existing assertions that legacy `agentLlmSettings`, `remoteLlmAnalysisSettings`, and weather credentials are physically absent from portable backup bytes.

- [ ] **Step 2: Run the focused RED/GREEN security suite**

Run: `flutter test test/backup_service_test.dart test/agent_chat_repository_test.dart test/windows_ai_credential_store_test.dart`

Expected: the new test initially fails only if chat tables are not copied/restored or a credential crossed the boundary; after the minimal correction, all pass.

- [ ] **Step 3: Run formatting, generation drift, and static analysis**

```powershell
dart format lib test
dart run build_runner build --delete-conflicting-outputs
git diff --exit-code -- lib/services/database/app_database.g.dart
dart analyze
```

Expected: generated code is stable; no new warning or error. The one pre-existing unnecessary-`!` warning may be cleaned only if its line is already touched; otherwise record it as baseline.

- [ ] **Step 4: Run the complete Flutter test suite**

Run: `flutter test`

Expected: all tests pass with no test load/compile failures.

- [ ] **Step 5: Run security and boundary scans**

```powershell
rg -n "/api/v1/agent|localAiConfigured|requestOpenAiSettings|AgentLlmSettings" lib test -g "*.dart"
rg -n "Authorization|apiKey|credential" lib/services/agent lib/features/agent -g "*.dart"
git diff --check
git status --short
```

Expected: obsolete API scan is empty; the security scan shows only intentional parameter/field labels and no logging or ordinary persistence; diff check is clean; unrelated dirty files remain preserved.

- [ ] **Step 6: Perform native Windows manual QA without exposing a real key**

Launch: `flutter run -d windows`.

Verify in the native app after the user unlocks the PIN:

1. Research is the only visible AI entry.
2. Opening AI and its configuration performs no visible network activity or startup delay.
3. Configure Ollama with a disposable local model, or let the user privately enter a remote Key; never read, screenshot, log, or echo that Key.
4. Send one message, restart, and confirm history remains.
5. Delete the credential and confirm history remains while Send requests configuration.
6. Confirm the left history rail, concise copy, Markdown answer, error retry, and glass styling match the approved workbench language.

- [ ] **Step 7: Update progress and commit Task 8 evidence**

```powershell
git add test/backup_service_test.dart .superpowers/sdd/2026-08-09-workbench-ui/progress.md
git commit -m "test: verify local AI security and recovery"
```

Do not push until the user explicitly asks for the implementation branch to be uploaded.

---

## Official Protocol References

- OpenAI quickstart and model docs: `https://platform.openai.com/docs/quickstart/make-your-first-api-request`
- DeepSeek Chat Completion: `https://api-docs.deepseek.com/api/create-chat-completion`
- DeepSeek multi-round chat: `https://api-docs.deepseek.com/guides/multi_round_chat/`
- Ollama OpenAI compatibility: `https://docs.ollama.com/api/openai-compatibility`
- Moonshot prompt/messages guide: `https://platform.moonshot.ai/docs/guide/prompt-best-practice`
- Zhipu chat completion: `https://open.bigmodel.cn/api/paas/v4/chat/completions`
