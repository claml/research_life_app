import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:research_life/core/models/app_models.dart';
import 'package:research_life/services/database/app_database.dart';
import 'package:research_life/services/database/repositories/preferences_repository.dart';

void main() {
  late AppDatabase database;
  late PreferencesRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = PreferencesRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('saves and loads weekly prompt template', () async {
    await repository.saveWeeklyPromptTemplate('test template');

    expect(await repository.loadWeeklyPromptTemplate(), 'test template');
  });

  test('updates existing preference by key', () async {
    await repository.saveWeeklyPromptTemplate('first');
    await repository.saveWeeklyPromptTemplate('second');

    final rows = await database.select(database.preferences).get();

    expect(rows, hasLength(1));
    expect(rows.single.value, 'second');
  });

  test('saves and clears weather location preference', () async {
    await repository.saveWeatherLocation('{"city":"杭州"}');

    expect(await repository.loadWeatherLocation(), '{"city":"杭州"}');

    await repository.clearWeatherLocation();

    expect(await repository.loadWeatherLocation(), isNull);
  });

  test('saves and loads pdf reader preferences', () async {
    const preferences = PdfReaderPreferences(
      sideRailCollapsed: true,
      sideTab: 'annotations',
      highlightColorValue: 0xFF64B5F6,
    );

    await repository.savePdfReaderPreferences(jsonEncode(preferences.toJson()));

    final stored = await repository.loadPdfReaderPreferences();
    final decoded = PdfReaderPreferences.fromJson(
      (jsonDecode(stored!) as Map).cast<String, Object?>(),
    );

    expect(decoded.sideRailCollapsed, preferences.sideRailCollapsed);
    expect(decoded.sideTab, preferences.sideTab);
    expect(decoded.highlightColorValue, preferences.highlightColorValue);
  });

  test('saves and loads remote LLM analysis settings', () async {
    const settings = RemoteLlmAnalysisSettings(
      enableRemoteLlmAnalysis: true,
      remoteTimeoutSeconds: 60,
      fallbackToRules: true,
      strictJsonSchema: false,
    );

    await repository.saveRemoteLlmAnalysisSettings(
      jsonEncode(settings.toJson()),
    );

    final stored = await repository.loadRemoteLlmAnalysisSettings();
    final decoded = RemoteLlmAnalysisSettings.fromJson(
      (jsonDecode(stored!) as Map).cast<String, Object?>(),
    );

    expect(decoded.enableRemoteLlmAnalysis, isTrue);
    expect(decoded.remoteTimeoutSeconds, 60);
    expect(decoded.fallbackToRules, isTrue);
    expect(decoded.strictJsonSchema, isFalse);
  });
}
