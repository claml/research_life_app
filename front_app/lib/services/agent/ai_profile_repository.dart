import 'dart:convert';

import '../database/repositories/preferences_repository.dart';
import 'ai_profile.dart';

final class AiProfileRepository {
  const AiProfileRepository(this._preferences);

  final PreferencesRepository _preferences;

  Future<AiProviderProfile?> loadActive() async {
    final raw = await _preferences.loadString(
      PreferencesRepository.localAiProfileV1Key,
    );
    if (raw == null) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Invalid AI profile record');
    }
    return AiProviderProfile.fromJson(Map<String, Object?>.from(decoded));
  }

  Future<void> saveActive(AiProviderProfile profile) async {
    final validatedProfile = AiProviderProfile.fromJson(profile.toJson());
    await _preferences.saveString(
      PreferencesRepository.localAiProfileV1Key,
      jsonEncode(validatedProfile.toJson()),
    );
  }

  Future<void> clearActive() {
    return _preferences.deleteString(PreferencesRepository.localAiProfileV1Key);
  }
}
