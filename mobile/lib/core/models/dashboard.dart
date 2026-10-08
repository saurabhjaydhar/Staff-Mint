import '../utils/json.dart';
import 'attendance.dart';
import 'leave.dart';

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

class Dashboard {
  const Dashboard({
    required this.date,
    required this.counts,
    this.leaveRequests = const [],
    this.punchApprovals = const [],
    this.flags = const [],
    this.staffCount = 0,
    this.staffLimit = 0,
  });

  final String date;
  final DashboardCounts counts;
  final List<Leave> leaveRequests;
  final List<PunchApprovalItem> punchApprovals;
  final List<FlagItem> flags;
  final int staffCount;
  final int staffLimit;

  int get needsActionCount => leaveRequests.length + punchApprovals.length + flags.length;

  factory Dashboard.fromJson(Json j) {
    final na = asMap(j['needsAction']);
    final plan = asMap(j['plan']);
    return Dashboard(
      date: asString(j['date']),
      counts: DashboardCounts.fromJson(asMap(j['counts'])),
      leaveRequests: asList(na['leaveRequests'], Leave.fromJson),
      punchApprovals: asList(na['punchApprovals'], PunchApprovalItem.fromJson),
      flags: asList(na['flags'], FlagItem.fromJson),
      staffCount: asInt(plan['staffCount']),
      staffLimit: asInt(plan['staffLimit']),
    );
  }
}
