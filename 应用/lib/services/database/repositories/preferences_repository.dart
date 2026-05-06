import '../app_database.dart';

class PreferencesRepository {
  const PreferencesRepository(this._database);

  static const weeklyPromptTemplateKey = 'weeklyPromptTemplate';
  static const colorThemeKey = 'colorTheme';
  static const weatherLocationKey = 'weatherLocation';
  static const vPetCompanionKey = 'vPetCompanion';
  static const pdfReaderPreferencesKey = 'pdfReaderPreferences';
  static const localLlmAnalysisSettingsKey = 'localLlmAnalysisSettings';

  final AppDatabase _database;

  Future<String?> loadString(String key) async {
    final row = await (_database.select(
      _database.preferences,
    )..where((preference) => preference.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> saveString(String key, String value) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _database
        .into(_database.preferences)
        .insertOnConflictUpdate(
          PreferencesCompanion.insert(key: key, value: value, updatedAt: now),
        );
  }

  Future<void> deleteString(String key) async {
    await (_database.delete(
      _database.preferences,
    )..where((preference) => preference.key.equals(key))).go();
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

  Future<String?> loadVPetCompanionSettings() {
    return loadString(vPetCompanionKey);
  }

  Future<void> saveVPetCompanionSettings(String settingsJson) {
    return saveString(vPetCompanionKey, settingsJson);
  }

  Future<String?> loadPdfReaderPreferences() {
    return loadString(pdfReaderPreferencesKey);
  }

  Future<void> savePdfReaderPreferences(String preferencesJson) {
    return saveString(pdfReaderPreferencesKey, preferencesJson);
  }

  Future<String?> loadLocalLlmAnalysisSettings() {
    return loadString(localLlmAnalysisSettingsKey);
  }

  Future<void> saveLocalLlmAnalysisSettings(String settingsJson) {
    return saveString(localLlmAnalysisSettingsKey, settingsJson);
  }
}
