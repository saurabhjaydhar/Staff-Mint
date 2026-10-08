import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_id.dart';
import 'key_value_store.dart';
import 'prefs_store.dart';
import 'token_storage.dart';

/// Must be overridden in `main()` (and tests) with a loaded instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider not overridden'),
);

/// Secure store for tokens. Overridden with [MemoryKeyValueStore] in tests.
final secureStoreProvider = Provider<KeyValueStore>((ref) => SecureKeyValueStore());

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage(ref.watch(secureStoreProvider)));

final deviceIdServiceProvider = Provider<DeviceIdService>(
  (ref) => DeviceIdService(PrefsKeyValueStore(ref.watch(sharedPreferencesProvider))),
);
