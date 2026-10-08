import 'package:shared_preferences/shared_preferences.dart';

import 'key_value_store.dart';

/// Non-secret preferences (language, device id) in SharedPreferences.
class PrefsKeyValueStore implements KeyValueStore {
  PrefsKeyValueStore(this._prefs);
  final SharedPreferences _prefs;

  @override
  Future<String?> read(String key) async => _prefs.getString(key);

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, value);
    }
  }

  @override
  Future<void> delete(String key) async => _prefs.remove(key);
}
