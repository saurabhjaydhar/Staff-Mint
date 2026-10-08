import 'package:uuid/uuid.dart';

import 'key_value_store.dart';

/// Stable per-install identifier used for employee device binding.
class DeviceIdService {
  DeviceIdService(this._store, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  static const _key = 'sm_device_id';
  final KeyValueStore _store;
  final Uuid _uuid;
  String? _cached;

  Future<String> getDeviceId() async {
    if (_cached != null) return _cached!;
    var id = await _store.read(_key);
    if (id == null || id.isEmpty) {
      id = _uuid.v4();
      await _store.write(_key, id);
    }
    return _cached = id;
  }
}
