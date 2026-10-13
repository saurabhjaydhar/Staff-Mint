import '../../models/models.dart';
import '../../utils/json.dart';
import '../api_client.dart';

class RosterApi {
  RosterApi(this._c);
  final ApiClient _c;

  Future<RosterWeek> week(String date) async =>
      RosterWeek.fromJson(asMap(await _c.get('/roster', query: {'week': date})));

  /// Saved as "not sent to staff yet". kind: `shift`, `off` or `usual` (back to their usual shift).
  Future<void> setCells(List<({String employeeId, String date, String kind, String? shiftId})> cells) => _c.put(
    '/roster/cells',
    body: {
      'cells': [
        for (final c in cells) {'employeeId': c.employeeId, 'date': c.date, 'kind': c.kind, 'shiftId': ?c.shiftId},
      ],
    },
  );

  Future<int> copyLastWeek(String week) async =>
      asInt(asMap(await _c.post('/roster/copy-last-week', body: {'week': week}))['copied']);

  /// Returns how many staff were told.
  Future<int> send(String week) async => asInt(asMap(await _c.post('/roster/send', body: {'week': week}))['sentTo']);

  Future<MyRosterWeek> mine(String date) async =>
      MyRosterWeek.fromJson(asMap(await _c.get('/roster/mine', query: {'week': date})));
}
