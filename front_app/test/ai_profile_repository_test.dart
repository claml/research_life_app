import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/services/agent/ai_profile.dart';
import 'package:research_life/services/agent/ai_profile_repository.dart';
import 'package:research_life/services/database/app_database.dart';
import 'package:research_life/services/database/repositories/preferences_repository.dart';
import 'package:research_life/services/storage/local_data_operation_coordinator.dart';

void main() {
  const profile = AiProviderProfile(
    id: 'primary',
    provider: 'deepseek',
    displayName: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-v4-flash',
    requiresCredential: true,
  );

  late AppDatabase database;
  late PreferencesRepository preferences;
  late AiProfileRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    preferences = PreferencesRepository(database);
    repository = AiProfileRepository(preferences);
  });

  tearDown(() async {
    await database.close();
  });

  test('profile JSON round-trip never has a credential field', () {
    final json = profile.toJson();

    expect(json.keys, isNot(contains('apiKey')));
    expect(json.keys, isNot(contains('credential')));
    expect(AiProviderProfile.fromJson(json), profile);
  });

  test('profile JSON rejects values that are not already trimmed', () {
    expect(
      () => AiProviderProfile.fromJson({
        'id': ' primary',
        'provider': 'deepseek',
        'displayName': 'DeepSeek',
        'baseUrl': 'https://api.deepseek.com',
        'model': 'deepseek-v4-flash',
        'requiresCredential': true,
      }),
      throwsFormatException,
    );
  });

  test('provider presets cover the six editable approved choices', () {
    expect(aiProviderPresets.map((preset) => preset.provider), [
      'deepseek',
      'openai',
      'moonshot',
      'zhipu',
      'ollama',
      'custom',
    ]);
    expect(
      aiProviderPresets
          .singleWhere((preset) => preset.provider == 'ollama')
          .requiresCredential,
      isFalse,
    );
    expect(
      aiProviderPresets
          .singleWhere((preset) => preset.provider == 'custom')
          .model,
      isEmpty,
    );
  });

  test('repository stores one active non-secret profile', () async {
    await repository.saveActive(profile);

    expect(await repository.loadActive(), profile);

    await repository.clearActive();

    expect(await repository.loadActive(), isNull);
  });

  test(
    'saveActive rejects a pure-whitespace profile field without writing',
    () async {
      final invalidProfile = AiProviderProfile(
        id: ' ',
        provider: 'deepseek',
        displayName: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-v4-flash',
        requiresCredential: true,
      );

      await expectLater(
        repository.saveActive(invalidProfile),
        throwsFormatException,
      );

      expect(
        await preferences.loadString(PreferencesRepository.localAiProfileV1Key),
        isNull,
      );
    },
  );

  test(
    'saveActive rejects a profile field with surrounding whitespace without writing',
    () async {
      final invalidProfile = AiProviderProfile(
        id: 'primary',
        provider: 'deepseek',
        displayName: 'DeepSeek',
        baseUrl: ' https://api.deepseek.com ',
        model: 'deepseek-v4-flash',
        requiresCredential: true,
      );

      await expectLater(
        repository.saveActive(invalidProfile),
        throwsFormatException,
      );

      expect(
        await preferences.loadString(PreferencesRepository.localAiProfileV1Key),
        isNull,
      );
    },
  );

  test('saveActive waits for the preferences coordinator lease', () async {
    final coordinator = LocalDataOperationCoordinator();
    final coordinatedPreferences = PreferencesRepository(
      database,
      operationCoordinator: coordinator,
    );
    final coordinatedRepository = AiProfileRepository(coordinatedPreferences);
    final leaseStarted = Completer<void>();
    final releaseLease = Completer<void>();
    var saveCompleted = false;

    final lease = coordinator.runExclusive(() async {
      leaseStarted.complete();
      await releaseLease.future;
    });
    await leaseStarted.future;
    final save = coordinatedRepository.saveActive(profile).then((_) {
      saveCompleted = true;
    });
    await Future<void>.delayed(Duration.zero);

    expect(saveCompleted, isFalse);
    expect(await coordinatedRepository.loadActive(), isNull);

    releaseLease.complete();
    await Future.wait([lease, save]);

    expect(await coordinatedRepository.loadActive(), profile);
  });
}
