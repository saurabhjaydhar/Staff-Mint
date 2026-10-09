import '../utils/json.dart';
import 'company.dart';
import 'employee.dart';

class PunchGeo {
  const PunchGeo({required this.lat, required this.lng, this.accuracyM});
  final double lat;
  final double lng;
  final double? accuracyM;

  factory PunchGeo.fromJson(Json j) =>
      PunchGeo(lat: asDouble(j['lat']), lng: asDouble(j['lng']), accuracyM: asDoubleOrNull(j['accuracyM']));
}

class Punch {
  const Punch({
    required this.id,
    required this.type,
    required this.clientTime,
    this.serverTime,
    this.geo,
    this.distanceM,
    this.insideGeofence,
    this.selfieUrl,
    this.mockLocation = false,
    this.lockCheck,
    this.deviceId,
    this.source = 'app',
    this.flags = const [],
    this.approval = 'not_required',
  });

  final String id;
  final String type; // in | out
  final DateTime clientTime;
  final DateTime? serverTime;
  final PunchGeo? geo;
  final num? distanceM;
  final bool? insideGeofence;
  final String? selfieUrl;
  final bool mockLocation;

  /// passed | failed | unavailable — the phone screen-lock result, null when not asked.
  final String? lockCheck;
  final String? deviceId;
  final String source;
  final List<String> flags;
  final String approval;

  bool get isIn => type == 'in';
  bool get isPendingApproval => approval == 'pending';

  factory Punch.fromJson(Json j) => Punch(
    id: asString(j['id']),
    type: asString(j['type'], 'in'),
    clientTime: asDateTimeOrNull(j['clientTime']) ?? asDateTimeOrNull(j['serverTime']) ?? DateTime.now(),
    serverTime: asDateTimeOrNull(j['serverTime']),
    geo: j['geo'] is Map ? PunchGeo.fromJson(asMap(j['geo'])) : null,
    distanceM: j['distanceM'] == null ? null : asNum(j['distanceM']),
    insideGeofence: j['insideGeofence'] == null ? null : asBool(j['insideGeofence']),
    selfieUrl: asStringOrNull(j['selfieUrl']),
    mockLocation: asBool(j['mockLocation']),
    lockCheck: asStringOrNull(j['lockCheck']),
    deviceId: asStringOrNull(j['deviceId']),
    source: asString(j['source'], 'app'),
    flags: asStringList(j['flags']),
    approval: asString(j['approval'], 'not_required'),
  );
}

class Attendance {
  const Attendance({
    required this.id,
    required this.employeeId,
    required this.date,
    this.status,
    this.leaveType,
    this.punches = const [],
    this.lateMinutes = 0,
    this.earlyOutMinutes = 0,
    this.workedMinutes = 0,
    this.overridden = false,
    this.overrideReason,
    this.flags = const [],
  });

  final String id;
  final String employeeId;
  final String date;
  final String? status;
  final String? leaveType;
  final List<Punch> punches;
  final int lateMinutes;
  final int earlyOutMinutes;
  final int workedMinutes;
  final bool overridden;
  final String? overrideReason;
  final List<String> flags;

  Punch? get firstIn {
    for (final p in punches) {
      if (p.isIn) return p;
    }
    return null;
  }

  Punch? get lastOut {
    for (final p in punches.reversed) {
      if (!p.isIn) return p;
    }
    return null;
  }

  factory Attendance.fromJson(Json j) {
    final punches = asList(j['punches'], Punch.fromJson)..sort((a, b) => a.clientTime.compareTo(b.clientTime));
    return Attendance(
      id: asString(j['id']),
      employeeId: asString(j['employeeId']),
      date: asString(j['date']),
      status: asStringOrNull(j['status']),
      leaveType: asStringOrNull(j['leaveType']),
      punches: punches,
      lateMinutes: asInt(j['lateMinutes']),
      earlyOutMinutes: asInt(j['earlyOutMinutes']),
      workedMinutes: asInt(j['workedMinutes']),
      overridden: asBool(j['overridden']),
      overrideReason: asStringOrNull(j['overrideReason']),
      flags: asStringList(j['flags']),
    );
  }
}

class DayRow {
  const DayRow({required this.employee, this.record, required this.displayStatus});
  final EmployeeRef employee;
  final Attendance? record;
  final String displayStatus;

  /// Row rebuilt from a fresh record (e.g. the response of an override).
  /// Holiday / week-off / leave rows without a record keep [fallback].
  DayRow withRecord(Attendance? r, {String? fallback}) => DayRow(
    employee: employee,
    record: r,
    displayStatus: displayStatusFor(r, fallback: fallback),
  );

  /// Mirrors the server's `displayStatus` for a single record.
  static String displayStatusFor(Attendance? r, {String? fallback}) {
    final st = r?.status;
    if (r == null || st == null) {
      if (r != null && r.firstIn != null && r.lastOut == null) return 'checked_in';
      return fallback ?? 'not_marked';
    }
    if (st == 'present' && r.lateMinutes > 0) return 'late';
    return st;
  }

  /// A punch is waiting for the owner's approve / reject.
  bool get needsCheck => record?.punches.any((p) => p.isPendingApproval) ?? false;

  /// Worst phone screen-lock result of the day: `failed` beats `unavailable`;
  /// null when every punch unlocked (or the lock was not asked).
  String? get lockIssue {
    final checks = (record?.punches ?? const <Punch>[]).where((p) => p.approval != 'rejected').map((p) => p.lockCheck);
    if (checks.contains('failed')) return 'failed';
    if (checks.contains('unavailable')) return 'unavailable';
    return null;
  }

  /// Farthest distance of a punch made outside the shop area, if any.
  num? get awayM {
    num? max;
    for (final p in record?.punches ?? const <Punch>[]) {
      if (p.insideGeofence == false && p.distanceM != null && (max == null || p.distanceM! > max)) max = p.distanceM;
    }
    return max;
  }

  factory DayRow.fromJson(Json j) => DayRow(
    employee: EmployeeRef.fromJson(asMap(j['employee'])),
    record: j['record'] is Map ? Attendance.fromJson(asMap(j['record'])) : null,
    displayStatus: asString(j['displayStatus'], 'not_marked'),
  );
}

/// `GET /attendance/today` for employees.
class TodayInfo {
  const TodayInfo({required this.date, this.record, this.shift, this.branch});
  final String date;
  final Attendance? record;
  final Shift? shift;
  final Branch? branch;

  factory TodayInfo.fromJson(Json j) => TodayInfo(
    date: asString(j['date']),
    record: j['record'] is Map ? Attendance.fromJson(asMap(j['record'])) : null,
    shift: j['shift'] is Map ? Shift.fromJson(asMap(j['shift'])) : null,
    branch: j['branch'] is Map ? Branch.fromJson(asMap(j['branch'])) : null,
  );
}

class MonthRow {
  const MonthRow({required this.employee, required this.days, required this.totals});
  final EmployeeRef employee;
  final Map<String, String> days;
  final Map<String, num> totals;

  factory MonthRow.fromJson(Json j) => MonthRow(
    employee: EmployeeRef.fromJson(asMap(j['employee'])),
    days: asMap(j['days']).map((k, v) => MapEntry(k, asString(v))),
    totals: asMap(j['totals']).map((k, v) => MapEntry(k, asNum(v))),
  );
}

class MonthGrid {
  const MonthGrid({required this.month, required this.days, required this.rows});
  final String month;
  final List<String> days;
  final List<MonthRow> rows;

  factory MonthGrid.fromJson(Json j) =>
      MonthGrid(month: asString(j['month']), days: asStringList(j['days']), rows: asList(j['rows'], MonthRow.fromJson));
}

class PunchApprovalItem {
  const PunchApprovalItem({required this.attendanceId, required this.employeeName, required this.punch});
  final String attendanceId;
  final String employeeName;
  final Punch punch;

  factory PunchApprovalItem.fromJson(Json j) => PunchApprovalItem(
    attendanceId: asString(j['attendanceId']),
    employeeName: asString(j['employeeName']),
    punch: Punch.fromJson(asMap(j['punch'])),
  );
}

class FlagItem {
  const FlagItem({required this.employeeName, required this.date, required this.flags});
  final String employeeName;
  final String date;
  final List<String> flags;

  factory FlagItem.fromJson(Json j) =>
      FlagItem(employeeName: asString(j['employeeName']), date: asString(j['date']), flags: asStringList(j['flags']));
}
