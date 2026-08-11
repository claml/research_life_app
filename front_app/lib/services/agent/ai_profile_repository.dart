import 'dart:convert';

import '../database/repositories/preferences_repository.dart';
import 'ai_profile.dart';

abstract interface class AiProfileStore {
  Future<AiProviderProfile?> loadActive();

  Future<void> saveActive(AiProviderProfile profile);

  Future<void> clearActive();
}

final class AiProfileRepository implements AiProfileStore {
  const AiProfileRepository(this._preferences);

  final PreferencesRepository _preferences;

  @override
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

  @override
  Future<void> saveActive(AiProviderProfile profile) async {
    final validatedProfile = AiProviderProfile.fromJson(profile.toJson());
    await _preferences.saveString(
      PreferencesRepository.localAiProfileV1Key,
      jsonEncode(validatedProfile.toJson()),
    );
  }

  @override
  Future<void> clearActive() {
    return _preferences.deleteString(PreferencesRepository.localAiProfileV1Key);
  }
}
