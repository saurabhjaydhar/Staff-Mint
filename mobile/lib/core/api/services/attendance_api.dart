import '../../models/models.dart';
import '../../utils/json.dart';
import '../api_client.dart';

class PunchResponse {
  const PunchResponse({required this.record, required this.punch});
  final Attendance record;
  final Punch punch;

  factory PunchResponse.fromJson(Json j) =>
      PunchResponse(record: Attendance.fromJson(asMap(j['record'])), punch: Punch.fromJson(asMap(j['punch'])));
}

class PunchSyncResult {
  const PunchSyncResult({required this.clientPunchId, required this.ok, this.errorCode, this.errorMessage});
  final String clientPunchId;
  final bool ok;
  final String? errorCode;
  final String? errorMessage;

  factory PunchSyncResult.fromJson(Json j) {
    final err = j['error'];
    String? code;
    String? message;
    if (err is Map) {
      code = asStringOrNull(err['code']);
      message = asStringOrNull(err['message']);
    } else if (err != null) {
      // Contract says `error?` without a shape: accept a plain string that is
      // either a code (UPPER_SNAKE) or a message.
      final s = err.toString();
      if (RegExp(r'^[A-Z_]+$').hasMatch(s)) {
        code = s;
      } else {
        message = s;
      }
    }
    return PunchSyncResult(
      clientPunchId: asString(j['clientPunchId']),
      ok: asBool(j['ok']),
      errorCode: code,
      errorMessage: message,
    );
  }
}

/// The subset of the attendance API used by the offline punch queue, so it
/// can be faked in tests.
abstract class PunchSyncApi {
  Future<List<PunchSyncResult>> syncPunches(List<Json> punches);
}

/// Online check-in / check-out (faked in tests).
abstract class PunchApi {
  Future<PunchResponse> checkIn(Json body);
  Future<PunchResponse> checkOut(Json body);
}

class AttendanceApi implements PunchSyncApi, PunchApi {
  AttendanceApi(this._c);
  final ApiClient _c;

  @override
  Future<PunchResponse> checkIn(Json body) async =>
      PunchResponse.fromJson(asMap(await _c.post('/attendance/check-in', body: body)));

  @override
  Future<PunchResponse> checkOut(Json body) async =>
      PunchResponse.fromJson(asMap(await _c.post('/attendance/check-out', body: body)));

  @override
  Future<List<PunchSyncResult>> syncPunches(List<Json> punches) async {
    final d = asMap(await _c.post('/attendance/sync', body: {'punches': punches}));
    return asList(d['results'], PunchSyncResult.fromJson);
  }

  Future<(TodayInfo, Json)> today() async {
    final d = asMap(await _c.get('/attendance/today'));
    return (TodayInfo.fromJson(d), d);
  }

  Future<List<DayRow>> day(String date) async =>
      asList(await _c.get('/attendance', query: {'date': date}), DayRow.fromJson);

  Future<MonthGrid> month(String month, {String? employeeId}) async =>
      MonthGrid.fromJson(asMap(await _c.get('/attendance/month', query: {'month': month, 'employeeId': employeeId})));

  Future<Attendance> overrideStatus({
    required String employeeId,
    required String date,
    required String status,
    String? leaveType,
    required String reason,
  }) async => Attendance.fromJson(
    asMap(
      await _c.post(
        '/attendance/override',
        body: {'employeeId': employeeId, 'date': date, 'status': status, 'leaveType': ?leaveType, 'reason': reason},
      ),
    ),
  );

  Future<Attendance> decidePunch(String attendanceId, String punchId, bool approve) async => Attendance.fromJson(
    asMap(await _c.post('/attendance/$attendanceId/punches/$punchId/decision', body: {'approve': approve})),
  );
}
