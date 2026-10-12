import '../utils/json.dart';
import 'attendance.dart';
import 'employee.dart';
import 'leave.dart';
import 'membership.dart';

class DashboardCounts {
  const DashboardCounts({
    this.total = 0,
    this.present = 0,
    this.late = 0,
    this.absent = 0,
    this.onLeave = 0,
    this.notMarked = 0,
    this.checkedIn = 0,
  });
  final int total;
  final int present;
  final int late;
  final int absent;
  final int onLeave;
  final int notMarked;
  final int checkedIn;

  factory DashboardCounts.fromJson(Json j) => DashboardCounts(
    total: asInt(j['total']),
    present: asInt(j['present']),
    late: asInt(j['late']),
    absent: asInt(j['absent']),
    onLeave: asInt(j['onLeave']),
    notMarked: asInt(j['notMarked']),
    checkedIn: asInt(j['checkedIn']),
  );
}

/// "Let's get your shop running": each step ticks itself on the server.
class HomeChecklist {
  const HomeChecklist({
    this.staffAdded = false,
    this.staffJoined = false,
    this.salarySet = false,
    this.teamAdded = false,
    this.staff = 0,
    this.joined = 0,
    this.notJoined = 0,
  });
  final bool staffAdded;
  final bool staffJoined;
  final bool salarySet;
  final bool teamAdded;
  final int staff;
  final int joined;
  final int notJoined;

  /// "Create your business" is always done.
  int get done => 1 + [staffAdded, staffJoined, salarySet, teamAdded].where((x) => x).length;
  static const total = 5;
  bool get complete => done == total;

  static HomeChecklist? fromJsonOrNull(Object? j) {
    if (j is! Map) return null;
    final m = asMap(j);
    final st = asMap(m['steps']);
    return HomeChecklist(
      staffAdded: asBool(st['staffAdded']),
      staffJoined: asBool(st['staffJoined']),
      salarySet: asBool(st['salarySet']),
      teamAdded: asBool(st['teamAdded']),
      staff: asInt(m['staff']),
      joined: asInt(m['joined']),
      notJoined: asInt(m['notJoined']),
    );
  }
}

class Dashboard {
  const Dashboard({
    required this.date,
    required this.counts,
    this.leaveRequests = const [],
    this.punchApprovals = const [],
    this.faceEnrollments = const [],
    this.flags = const [],
    this.deviceRequests = const [],
    this.staffCount = 0,
    this.staffLimit = 0,
    this.setup,
  });

  final String date;
  final DashboardCounts counts;
  final List<Leave> leaveRequests;
  final List<PunchApprovalItem> punchApprovals;
  final List<FaceEnrollment> faceEnrollments;
  final List<FlagItem> flags;
  final List<DeviceRequestItem> deviceRequests;
  final int staffCount;
  final int staffLimit;
  final HomeChecklist? setup;

  int get needsActionCount =>
      leaveRequests.length + punchApprovals.length + faceEnrollments.length + flags.length + deviceRequests.length;

  factory Dashboard.fromJson(Json j) {
    final na = asMap(j['needsAction']);
    final plan = asMap(j['plan']);
    return Dashboard(
      date: asString(j['date']),
      counts: DashboardCounts.fromJson(asMap(j['counts'])),
      leaveRequests: asList(na['leaveRequests'], Leave.fromJson),
      punchApprovals: asList(na['punchApprovals'], PunchApprovalItem.fromJson),
      faceEnrollments: asList(na['faceEnrollments'], FaceEnrollment.fromJson),
      flags: asList(na['flags'], FlagItem.fromJson),
      deviceRequests: asList(na['deviceRequests'], DeviceRequestItem.fromJson),
      staffCount: asInt(plan['staffCount']),
      staffLimit: asInt(plan['staffLimit']),
      setup: HomeChecklist.fromJsonOrNull(j['setup']),
    );
  }
}
