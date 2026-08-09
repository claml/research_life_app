# Weather, Optional Network, and Cloud Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the accepted Weather standby view with a beautiful static fallback and lightweight optional motion, enable local AI credentials without workbench login, remove dead cloud code, and complete Windows acceptance.

**Architecture:** Build Weather from a bundled accepted cloudscape plus isolated motion layers controlled by a pure policy. Store optional AI credentials in Windows Credential Manager through an interface. Only after runtime and UI reviews pass, delete unreachable auth/sync code and perform a separately protected Drift cleanup migration.

**Tech Stack:** Flutter animation/CustomPainter/RepaintBoundary, bundled PNG assets, `win32` Credential Manager APIs, Dio/ApiClient, Drift migration, Flutter tests, Windows desktop screenshots.

## Global Constraints

- Plans 1 and 2 must be accepted first.
- The static Weather composition is the quality baseline; motion may never replace it with a lower-quality fallback.
- Motion stops when disabled, reduced-motion is active, Weather is offstage, or `TickerMode` is false.
- Time updates do not repaint Weather background layers.
- Weather and AI failures remain local to their views.
- AI exists only in Research and credentials never enter the database, logs, exported settings, or backups.
- A validated safety backup is mandatory immediately before the schema cleanup migration.
- Do not initialize Git; use SDD checkpoints and independent review.

---

## File Structure

**Create**

- `assets/weather/weather_cloudscape.png` — project asset derived from the accepted Web Weather background.
- `lib/features/weather/weather_standby_view.dart` — Weather composition, return control, information panel.
- `lib/features/weather/weather_motion_policy.dart` — pure enable/disable decision.
- `lib/features/weather/weather_motion_layer.dart` — cloud/light/particle animation only.
- `lib/services/credentials/local_credential_store.dart` — credential interface.
- `lib/services/credentials/windows_credential_store.dart` — `win32` Credential Manager implementation.
- `lib/services/analysis/local_ai_client_factory.dart` — direct optional AI client independent of auth.
- `lib/services/analysis/openai_compatible_analysis_provider.dart` — direct weekly-analysis adapter.
- `lib/services/agent/openai_compatible_agent_api.dart` — direct Research AI conversation adapter.
- `lib/services/database/local_schema_migration_guard.dart` — validates the recorded migration backup before v9 opens.
- Tests for each unit.

**Modify**

- `pubspec.yaml`
- `lib/app/workbench_shell.dart`
- `lib/shared/widgets/frosted_glass.dart`
- `lib/state/research_life_controller.dart`
- `lib/features/settings/settings_page.dart`
- `lib/features/agent/agent_page.dart`
- `lib/services/database/app_database.dart` and generated `app_database.g.dart` during cleanup.

**Delete only after reference scan**

- `lib/app/auth_gate.dart`, `lib/app/auth_scope.dart`, `lib/state/auth_controller.dart`
- `lib/features/auth/**`, `lib/features/sync/**`
- `lib/services/auth/**`, `lib/services/sync/**`
- Cloud-only file widgets and auth/sync tests.

---

### Task 1: Accepted Static Weather Composition

**Files:**
- Create: `assets/weather/weather_cloudscape.png`
- Modify: `pubspec.yaml`
- Create: `lib/features/weather/weather_standby_view.dart`
- Modify: `lib/app/workbench_shell.dart`
- Test: `test/weather_standby_view_test.dart`

**Interfaces:**
- Produces: `WeatherStandbyView(onExit, snapshot, animationEnabled, onAnimationToggle)`.
- Consumes: the navigation controller Weather snapshot/exit behavior from Plan 2.

- [ ] **Step 1: Add the accepted asset with provenance**

Copy `docs/workbench_preview/assets/weather-cloudscape.png` to `assets/weather/weather_cloudscape.png`. Record source and SHA-256 in the task report. Register only the `assets/weather/` directory in `pubspec.yaml`.

- [ ] **Step 2: Write failing static composition tests**

```dart
testWidgets('static Weather keeps cloudscape, return, time, and at most three items', (tester) async {
  await tester.pumpWidget(testApp(
    WeatherStandbyView(
      snapshot: fixtureSnapshot,
      animationEnabled: false,
      onAnimationToggle: (_) {},
      onExit: () {},
    ),
  ));
  final image = tester.widget<Image>(find.byKey(const Key('weather-cloudscape')));
  expect(image.image, isA<AssetImage>());
  expect(find.bySemanticsLabel('返回工作台'), findsOneWidget);
  expect(find.byKey(const Key('weather-agenda-item')), findsNWidgets(3));
  expect(find.byKey(const Key('weather-motion-layer')), findsNothing);
});
```

- [ ] **Step 3: Run RED**

```powershell
flutter test test\weather_standby_view_test.dart
```

- [ ] **Step 4: Implement the static composition**

Use `StackFit.expand`, `Image.asset(..., fit: BoxFit.cover, filterQuality: FilterQuality.high)`, a subtle non-animated scrim, one left information surface, Return at top-left, and animation/reduced-transparency control at bottom-right. The information surface contains time/date, condition, details, and at most three Today items.

- [ ] **Step 5: Keep the clock isolated**

Place the one-second clock in its own `StatefulWidget` and `RepaintBoundary`. The asset image and information panel must not listen to the clock ticker.

- [ ] **Step 6: Run GREEN and inspect 1280×800**

```powershell
flutter test test\weather_standby_view_test.dart
```

Capture a Windows screenshot with animation disabled and compare it to `docs/workbench_preview/assets/concepts/weather.png` at original detail.

- [ ] **Step 7: Record Task 1 checkpoint and visual review**

---

### Task 2: Motion Policy and Lightweight Weather Layers

**Files:**
- Create: `lib/features/weather/weather_motion_policy.dart`
- Create: `lib/features/weather/weather_motion_layer.dart`
- Modify: `lib/features/weather/weather_standby_view.dart`
- Test: `test/weather_motion_policy_test.dart`
- Test: `test/weather_motion_layer_test.dart`

**Interfaces:**
- Produces: `WeatherMotionPolicy.shouldAnimate({userEnabled, reduceMotion, tickerEnabled, visible})`.
- Produces: `WeatherMotionLayer(condition, isDay, animation)`.

- [ ] **Step 1: Write the failing policy matrix**

```dart
for (final row in [
  (user: true, reduce: false, ticker: true, visible: true, expected: true),
  (user: false, reduce: false, ticker: true, visible: true, expected: false),
  (user: true, reduce: true, ticker: true, visible: true, expected: false),
  (user: true, reduce: false, ticker: false, visible: true, expected: false),
  (user: true, reduce: false, ticker: true, visible: false, expected: false),
]) {
  test('motion policy $row', () {
    expect(
      WeatherMotionPolicy.shouldAnimate(
        userEnabled: row.user,
        reduceMotion: row.reduce,
        tickerEnabled: row.ticker,
        visible: row.visible,
      ),
      row.expected,
    );
  });
}
```

- [ ] **Step 2: Run RED**

```powershell
flutter test test\weather_motion_policy_test.dart test\weather_motion_layer_test.dart
```

- [ ] **Step 3: Implement a single animation controller**

The layer uses one 24-second controller. Two translucent cloud masks move no more than 12 logical pixels in opposite directions; the light veil varies opacity within 0.04; rain/snow particles are capped at 40 and painted by one `CustomPainter`. Sunny/unknown conditions render no particles.

- [ ] **Step 4: Stop and restart the ticker correctly**

Use `TickerMode.of(context)`, `MediaQuery.disableAnimations`, the user preference, and Weather visibility to call `repeat()` or `stop()`. Do not keep a repeating controller while the static branch is displayed.

- [ ] **Step 5: Add repaint-boundary tests**

Assert the static image, motion layer, clock, and information panel each have their own keyed `RepaintBoundary`; pump one second and verify the motion controller value does not advance when reduced motion is true.

- [ ] **Step 6: Run GREEN and Windows motion QA**

```powershell
flutter test test\weather_motion_policy_test.dart test\weather_motion_layer_test.dart test\weather_standby_view_test.dart
```

Observe for at least 30 seconds at 1280×800. Reject motion that draws attention away from time or text. Verify disabling animation freezes on the accepted static composition rather than a gradient.

- [ ] **Step 7: Record Task 2 checkpoint and review**

---

### Task 3: Selective Glass and Accessibility Fallbacks

**Files:**
- Modify: `lib/shared/widgets/frosted_glass.dart`
- Modify: `lib/features/weather/weather_standby_view.dart`
- Modify: `lib/core/theme/app_tokens.dart`
- Test: `test/glass_settings_test.dart`
- Test: `test/weather_accessibility_test.dart`

**Interfaces:**
- Produces: `FrostedGlass(reducedTransparency, blurEnabled)` with a fully opaque branch that creates no `BackdropFilter`.

- [ ] **Step 1: Write failing opaque-fallback tests**

```dart
testWidgets('reduced transparency creates no BackdropFilter', (tester) async {
  await tester.pumpWidget(testApp(
    const FrostedGlass(
      reducedTransparency: true,
      child: Text('内容'),
    ),
  ));
  expect(find.byType(BackdropFilter), findsNothing);
  expect(find.text('内容'), findsOneWidget);
});
```

- [ ] **Step 2: Run RED**

```powershell
flutter test test\glass_settings_test.dart test\weather_accessibility_test.dart
```

- [ ] **Step 3: Implement the structural fallback**

Do not merely set blur sigma to zero. Return an opaque decorated container before constructing `BackdropFilter`. Preserve border radius, padding, focus ring, and contrast.

- [ ] **Step 4: Verify keyboard and semantics**

Return, animation toggle, reduced transparency, weather refresh, and city selection must be reachable by Tab with visible focus. Escape exits Weather and returns focus to the Weather navigation icon.

- [ ] **Step 5: Run GREEN and record checkpoint**

---

### Task 4: Windows Credential Store and Local AI Client

**Files:**
- Create: `lib/services/credentials/local_credential_store.dart`
- Create: `lib/services/credentials/windows_credential_store.dart`
- Create: `lib/services/analysis/local_ai_client_factory.dart`
- Modify: `lib/app/local_app_runtime.dart`
- Modify: `lib/features/settings/settings_page.dart`
- Modify: `lib/features/agent/agent_page.dart`
- Test: `test/local_credential_store_test.dart`
- Test: `test/local_ai_client_factory_test.dart`

**Interfaces:**
- Produces: `LocalCredentialStore.read/write/delete(String key)`.
- Produces: `LocalAiClientFactory.createDio(LocalAiConfiguration config, String apiKey)` with no workbench auth callback.
- Produces: OpenAI-compatible analysis and Research chat adapters sharing that Dio client.

- [ ] **Step 1: Define and test the credential interface with an in-memory fake**

```dart
abstract interface class LocalCredentialStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

test('AI key round trips without entering exported preferences', () async {
  final store = InMemoryCredentialStore();
  await store.write('research-life.ai.api-key', 'secret');
  expect(await store.read('research-life.ai.api-key'), 'secret');
  expect(exportedPreferencesJson, isNot(contains('secret')));
});
```

- [ ] **Step 2: Run RED**

```powershell
flutter test test\local_credential_store_test.dart test\local_ai_client_factory_test.dart
```

- [ ] **Step 3: Implement Windows Credential Manager adapter**

Use existing `win32` `CredWrite`, `CredRead`, `CredDelete`, and `CredFree` APIs with `CRED_TYPE_GENERIC` and `CRED_PERSIST_LOCAL_MACHINE`. Allocate and free every native string/blob in `try/finally`. Store UTF-8 bytes and reject values larger than the Windows generic credential blob limit. Convert Win32 failures into `CredentialStoreException` without including the credential value.

- [ ] **Step 4: Implement auth-independent AI client construction**

```dart
Dio createDio(LocalAiConfiguration config, String apiKey) {
  return Dio(BaseOptions(
    baseUrl: config.baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 90),
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $apiKey',
    },
  ));
}
```

The analysis adapter posts OpenAI-compatible chat-completion requests and returns the validated JSON expected by `AnalysisResultValidator`. The agent adapter implements the existing Research conversation interface using the same endpoint/model settings. A 401 becomes a local “凭据无效” error and never changes application navigation or startup state.

- [ ] **Step 5: Add Settings save/test/delete flow**

The API key field never displays the stored secret. Saving an empty field leaves the current secret unchanged; `删除凭据` is a separate confirmed action. `测试连接` reports only status and provider/model, never request headers.

- [ ] **Step 6: Run GREEN and inspect logs**

```powershell
flutter test test\local_credential_store_test.dart test\local_ai_client_factory_test.dart
```

Search test output and app logs for the fixture secret and expect zero matches.

- [ ] **Step 7: Record Task 4 checkpoint and security review**

---

### Task 5: Remove Dead Auth/Sync/Cloud Code

**Files:**
- Delete only files proven unreachable under `lib/app/auth_*`, `lib/state/auth_controller.dart`, `lib/services/auth/**`, `lib/services/sync/**`, `lib/features/auth/**`, `lib/features/sync/**`, and cloud-only file widgets.
- Modify imports and tests throughout `lib/**` and `test/**`.
- Create: `.superpowers/sdd/2026-08-09-weather-cleanup/cloud-removal-inventory.md`

- [ ] **Step 1: Produce the reference inventory before deletion**

```powershell
rg -n "AuthScope|AuthController|AuthGate|FileSyncEngine|CloudFileService|SyncOutboxRepository|CloudFileEntry|cloudSync" lib test
```

Classify every match as active, legacy-to-delete, generated-schema, or historical test. No deletion starts while an active production match remains.

- [ ] **Step 2: Delete one bounded family at a time**

Order: auth UI/state/service → sync feature/service → cloud file widgets → cloud-only tests. After each family:

```powershell
flutter analyze
flutter test
```

Fix only actual broken local references; do not restore compatibility wrappers.

- [ ] **Step 3: Verify no cloud language remains in active UI**

```powershell
rg -n "登录|注册|退出登录|云同步|上传云端|云端文件|设备同步" lib
```

Allowed matches: none in active production copy. Comments describing migration history should move to docs, not remain in UI source.

- [ ] **Step 4: Record deleted files and test replacements**

The inventory lists each deleted source/test and the local behavior or new test that supersedes it. Request independent review before database migration.

---

### Task 6: Protected Drift Schema Cleanup

**Files:**
- Modify: `lib/services/database/app_database.dart`
- Regenerate: `lib/services/database/app_database.g.dart`
- Modify local repositories/models to remove sync-only fields.
- Create: `test/database_local_schema_migration_test.dart`
- Create: `lib/services/database/local_schema_migration_guard.dart`

**Interfaces:**
- Raises schema version from 8 to 9.
- Removes `SyncOutbox` and `SyncCursors` tables.
- Removes sync-only columns from Events, Notes, PdfLibraryDocuments, and PdfLibraryAnnotations while preserving local content and deletion semantics required by local repositories.

- [ ] **Step 1: Write a version-8 fixture migration test**

Create an actual v8 SQLite fixture with one row in every affected table, including local content and sync metadata. Open it with the v9 database and assert all local fields survive, sync tables are absent, and repository reads return the same records.

```dart
expect(await tableNames(database), isNot(contains('sync_outbox')));
expect(await tableNames(database), isNot(contains('sync_cursors')));
expect((await repository.loadManualEvents()).single.title, '保留的日程');
expect((await notesRepository.loadNotes()).single.contentMarkdown, '# 保留');
```

- [ ] **Step 2: Run RED**

```powershell
flutter test test\database_local_schema_migration_test.dart
```

- [ ] **Step 3: Require and validate a safety backup**

Before Drift opens the database, `LocalSchemaMigrationGuard` reads `local_mode.migration_backup_v1.complete` and `local_mode.migration_backup_v1.path` from the v8 `preferences` table through a read-only `sqlite3` connection, validates the referenced backup manifest and hashes, and refuses migration if either value or validation is missing.

- [ ] **Step 4: Define local-only tables and migration**

Remove sync-only columns from table definitions, remove `SyncOutbox`/`SyncCursors` from `@DriftDatabase`, and set `currentSchemaVersion = 9`. Exact removals: Events and Notes drop `syncVersion`, `syncState`, `deviceId`, `isDeleted`; PDF documents drop `serverId`, `syncVersion`, `syncState`, `deviceId`, `storageKey` but keep local `contentHash` and `isDeleted`; PDF annotations drop `serverId`, `syncVersion`, `syncState`, `deviceId` but keep local `isDeleted`.

Use Drift `TableMigration` so matching local columns copy automatically while old extra columns are discarded:

```dart
if (from < 9) {
  await customStatement('PRAGMA foreign_keys = OFF');
  await transaction(() async {
    await migrator.alterTable(TableMigration(events));
    await migrator.alterTable(TableMigration(notes));
    await migrator.alterTable(TableMigration(pdfLibraryDocuments));
    await migrator.alterTable(TableMigration(pdfLibraryAnnotations));
    await customStatement('DROP TABLE IF EXISTS sync_outbox');
    await customStatement('DROP TABLE IF EXISTS sync_cursors');
  });
  final brokenForeignKeys = await customSelect(
    'PRAGMA foreign_key_check',
  ).get();
  if (brokenForeignKeys.isNotEmpty) {
    throw StateError('v9 migration produced invalid foreign keys');
  }
}
```

Ensure `beforeOpen` always re-enables `PRAGMA foreign_keys = ON`, including after a failed migration.

- [ ] **Step 5: Regenerate Drift code**

```powershell
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 6: Run migration and full database tests**

```powershell
flutter test test\database_local_schema_migration_test.dart test\manual_events_repository_test.dart test\sessions_repository_test.dart test\todo_status_repository_test.dart
flutter analyze
```

- [ ] **Step 7: Perform a disposable real backup → migrate → restore drill**

Verify both directions: the v8 safety backup restores into a v8 fixture runtime, and the migrated v9 workspace can create and restore a new v9 backup. Never test against the user’s real workspace.

- [ ] **Step 8: Record Task 6 checkpoint and database review**

Critical review focus: data preservation, foreign keys, tombstone filtering, rollback, and migration precondition.

---

### Task 7: Final Verification, Fidelity, and Handoff

- [ ] **Step 1: Run clean automated verification**

```powershell
flutter analyze
flutter test
```

- [ ] **Step 2: Build Windows**

```powershell
flutter build windows
```

- [ ] **Step 3: Execute all product paths**

1. Offline start → Today → Calendar → create/edit/delete a manual event.
2. Materials → rename a folder with descendants → inspect/open PDF → run a local PDF action.
3. Research → configure AI credential → test invalid/valid credential behavior → ensure no login state appears.
4. Research Notes → Weather → wait 30 seconds → disable animation → Escape → confirm exact tab/selection/focus restoration.
5. Create backup → mutate local data → restore → verify files and records.

- [ ] **Step 4: Capture and compare native screenshots**

At 1280×800 capture Weather, Today, Research, and Materials; at approximately 980px capture compact Today and Materials. Inspect accepted concepts and current screenshots at original detail. Compare at least shared shell geometry, navigation state, academic green, selective glass, hierarchy, typography, Weather atmosphere, action placement, and copy differences.

- [ ] **Step 5: Run policy scans**

```powershell
rg -n "AuthScope|AuthController|AuthGate|FileSyncEngine|CloudFileService|SyncOutboxRepository|cloudSync" lib test
rg -n "BackdropFilter" lib
```

Expected first command: zero matches. Every `BackdropFilter` match must be in an allowed surface with an opaque fallback test.

- [ ] **Step 6: Request final whole-branch review**

Provide the confirmed spec, all three plans, task reports, fresh tests, build result, migration drill, file inventory, and visual fidelity ledger. Fix all Critical and Important findings before handoff.

- [ ] **Step 7: Deliver**

Leave the Windows app open on Today at 1280×800, provide the backup location and restore instructions, list intentional visual deviations, and explicitly state that login/cloud sync have been removed and Weather/AI are the only optional network features.
