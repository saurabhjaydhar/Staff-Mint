import 'dart:convert';

import '../utils/json.dart';
import 'key_value_store.dart';

/// Persists access/refresh tokens plus a cached `/me` payload so the app can
/// start (and employees can punch offline) without network.
class TokenStorage {
  TokenStorage(this._store);

  static const _kAccess = 'sm_access_token';
  static const _kRefresh = 'sm_refresh_token';
  static const _kSession = 'sm_session_cache';

  final KeyValueStore _store;
  String? _access;
  String? _refresh;
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _access = await _store.read(_kAccess);
    _refresh = await _store.read(_kRefresh);
    _loaded = true;
  }

  Future<String?> readAccessToken() async {
    await _ensureLoaded();
    return _access;
  }

  Future<String?> readRefreshToken() async {
    await _ensureLoaded();
    return _refresh;
  }

  Future<bool> hasSession() async => (await readAccessToken()) != null;

  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    _access = accessToken;
    _refresh = refreshToken;
    _loaded = true;
    await _store.write(_kAccess, accessToken);
    await _store.write(_kRefresh, refreshToken);
  }

  Future<Json?> readSessionCache() async {
    final raw = await _store.read(_kSession);
    if (raw == null) return null;
    try {
      return asMapOrNull(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> writeSessionCache(Json? json) => _store.write(_kSession, json == null ? null : jsonEncode(json));

  Future<void> clear() async {
    _access = null;
    _refresh = null;
    _loaded = true;
    await _store.delete(_kAccess);
    await _store.delete(_kRefresh);
    await _store.delete(_kSession);
  }
}
