import '../app_database.dart';
import '../../storage/local_data_operation_coordinator.dart';

abstract interface class LocalMigrationPreferences {
  Future<bool> loadLocalMigrationBackupComplete();

  Future<String?> loadLocalMigrationBackupPath();

  Future<void> saveLocalMigrationBackupRecord(String path);

  Future<void> invalidateLocalMigrationBackupRecord();
}

class PreferencesRepository implements LocalMigrationPreferences {
  const PreferencesRepository(
    this._database, {
    LocalDataOperationCoordinator? operationCoordinator,
  }) : _operationCoordinator = operationCoordinator;

  static const weeklyPromptTemplateKey = 'weeklyPromptTemplate';
  static const colorThemeKey = 'colorTheme';
  static const weatherLocationKey = 'weatherLocation';
  static const weatherApiKeyKey = 'weatherApiKey';
  static const weatherApiHostKey = 'weatherApiHost';
  static const weatherAnimationEnabledKey = 'weatherAnimationEnabled';
  static const petCompanionKey = 'petCompanion';
  static const pdfReaderPreferencesKey = 'pdfReaderPreferences';
  static const closeToTrayKey = 'closeToTray';
  static const remoteLlmAnalysisSettingsKey = 'remoteLlmAnalysisSettings';
  static const agentLlmSettingsKey = 'agentLlmSettings';
  static const localAiProfileV1Key = 'localAiProfileV1';
  static const glassSettingsKey = 'glassSettings';
  static const calendarReminderEnabledKey = 'calendarReminderEnabled';
  static const pinLockKey = 'pinLock';
  static const localMigrationBackupCompleteKey =
      'local_mode.migration_backup_v1.complete';
  static const localMigrationBackupPathKey =
      'local_mode.migration_backup_v1.path';

  final AppDatabase _database;
  final LocalDataOperationCoordinator? _operationCoordinator;

  Future<T> _write<T>(Future<T> Function() operation) {
    final coordinator = _operationCoordinator;
    return coordinator == null
        ? operation()
        : coordinator.runExclusive(operation);
  }

  Future<String?> loadString(String key) async {
    final row = await (_database.select(
      _database.preferences,
    )..where((preference) => preference.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> saveString(String key, String value) async {
    await _write(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _database
          .into(_database.preferences)
          .insertOnConflictUpdate(
            PreferencesCompanion.insert(key: key, value: value, updatedAt: now),
          );
    });
  }

  Future<void> deleteString(String key) async {
    await _write(() async {
      await (_database.delete(
        _database.preferences,
      )..where((preference) => preference.key.equals(key))).go();
    });
  }

  Future<String?> loadWeeklyPromptTemplate() {
    return loadString(weeklyPromptTemplateKey);
  }

  Future<void> saveWeeklyPromptTemplate(String template) {
    return saveString(weeklyPromptTemplateKey, template.trim());
  }

  Future<String?> loadColorTheme() {
    return loadString(colorThemeKey);
  }

  Future<void> saveColorTheme(String theme) {
    return saveString(colorThemeKey, theme.trim());
  }

  Future<String?> loadWeatherLocation() {
    return loadString(weatherLocationKey);
  }

  Future<void> saveWeatherLocation(String locationJson) {
    return saveString(weatherLocationKey, locationJson.trim());
  }

  Future<void> clearWeatherLocation() {
    return deleteString(weatherLocationKey);
  }

  Future<String?> loadWeatherApiKey() {
    return loadString(weatherApiKeyKey);
  }

  Future<void> saveWeatherApiKey(String apiKey) {
    return saveString(weatherApiKeyKey, apiKey.trim());
  }

  Future<String?> loadWeatherApiHost() {
    return loadString(weatherApiHostKey);
  }

  Future<void> saveWeatherApiHost(String apiHost) {
    return saveString(weatherApiHostKey, apiHost.trim());
  }

  Future<bool?> loadWeatherAnimationEnabled() async {
    final raw = await loadString(weatherAnimationEnabledKey);
    if (raw == null) {
      return null;
    }
    return raw == 'true';
  }

  Future<void> saveWeatherAnimationEnabled(bool enabled) {
    return saveString(weatherAnimationEnabledKey, enabled ? 'true' : 'false');
  }

  Future<bool> loadCloseToTray() async {
    return (await loadString(closeToTrayKey)) != 'false';
  }

  Future<void> saveCloseToTray(bool enabled) {
    return saveString(closeToTrayKey, enabled ? 'true' : 'false');
  }

  Future<String?> loadPetCompanionSettings() {
    return loadString(petCompanionKey);
  }

  Future<void> savePetCompanionSettings(String settingsJson) {
    return saveString(petCompanionKey, settingsJson);
  }

  Future<String?> loadPdfReaderPreferences() {
    return loadString(pdfReaderPreferencesKey);
  }

  Future<void> savePdfReaderPreferences(String preferencesJson) {
    return saveString(pdfReaderPreferencesKey, preferencesJson);
  }

  Future<String?> loadRemoteLlmAnalysisSettings() {
    return loadString(remoteLlmAnalysisSettingsKey);
  }

  Future<void> saveRemoteLlmAnalysisSettings(String settingsJson) {
    return saveString(remoteLlmAnalysisSettingsKey, settingsJson);
  }

  Future<String?> loadGlassSettings() {
    return loadString(glassSettingsKey);
  }

  Future<void> saveGlassSettings(String settingsJson) {
    return saveString(glassSettingsKey, settingsJson);
  }

  Future<bool?> loadCalendarReminderEnabled() async {
    final raw = await loadString(calendarReminderEnabledKey);
    if (raw == null) {
      return null;
    }
    return raw == 'true';
  }

  Future<void> saveCalendarReminderEnabled(bool enabled) {
    return saveString(calendarReminderEnabledKey, enabled ? 'true' : 'false');
  }

  Future<String?> loadPinLock() {
    return loadString(pinLockKey);
  }

  Future<void> savePinLock(String pinLockJson) {
    return saveString(pinLockKey, pinLockJson);
  }

  Future<void> deletePinLock() {
    return deleteString(pinLockKey);
  }

  @override
  Future<bool> loadLocalMigrationBackupComplete() async {
    return await loadString(localMigrationBackupCompleteKey) == 'true';
  }

  @override
  Future<String?> loadLocalMigrationBackupPath() {
    return loadString(localMigrationBackupPathKey);
  }

  @override
  Future<void> saveLocalMigrationBackupRecord(String path) {
    return _write(() async {
      await _database.transaction(() async {
        await saveString(localMigrationBackupPathKey, path);
        await saveString(localMigrationBackupCompleteKey, 'true');
      });
    });
  }

  @override
  Future<void> invalidateLocalMigrationBackupRecord() {
    return _write(() async {
      // Delete the completion marker first. If clearing the stale path fails,
      // the durable state remains safely incomplete and can be retried.
      await deleteString(localMigrationBackupCompleteKey);
      await deleteString(localMigrationBackupPathKey);
    });
  }
}
