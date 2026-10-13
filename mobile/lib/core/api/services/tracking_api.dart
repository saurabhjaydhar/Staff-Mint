import '../../models/models.dart';
import '../../utils/json.dart';
import '../api_client.dart';

class TrackingApi {
  TrackingApi(this._c);
  final ApiClient _c;

  // ---- Owner / manager
  /// Field staff on or off. Returns whether it's on and whether they agreed.
  Future<({bool enabled, bool consented})> setFor(String employeeId, bool enabled) async {
    final j = asMap(await _c.put('/tracking/employees/$employeeId', body: {'enabled': enabled}));
    return (enabled: asBool(j['enabled']), consented: asBool(j['consented']));
  }

  // ---- Staff
  Future<MyTracking> me() async => MyTracking.fromJson(asMap(await _c.get('/tracking/me')));
  Future<MyTracking> consent() async => MyTracking.fromJson(asMap(await _c.post('/tracking/me/consent')));
  Future<MyTracking> withdraw() async => MyTracking.fromJson(asMap(await _c.delete('/tracking/me/consent')));

  Future<PingResult> pings(List<Json> points) async =>
      PingResult.fromJson(asMap(await _c.post('/tracking/pings', body: {'points': points})));

  Future<void> events(List<Json> events) async => _c.post('/tracking/events', body: {'events': events});
}
