import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdService {
  static const _prefsKey = 'research_life_device_id';

  Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_prefsKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final generated = _generateId();
    await prefs.setString(_prefsKey, generated);
    return generated;
  }

  String _generateId() {
    final random = Random.secure();
    final buffer = StringBuffer('dev_');
    for (var index = 0; index < 24; index++) {
      buffer.write(random.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }
}
