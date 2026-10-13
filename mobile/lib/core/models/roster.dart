import '../utils/json.dart';
import 'company.dart';

/// One person's plan for one day: a shift, or a day off.
class RosterCell {
  const RosterCell({
    required this.date,
    required this.kind,
    this.shiftId,
    this.usual = true,
    this.changed = false,
    this.leave,
    this.employed = true,
  });
  final String date;

  /// `shift` or `off`.
  final String kind;
  final String? shiftId;

  /// Comes from the person's usual shift and weekly off, not the roster.
  final bool usual;

  /// Changed but not sent to staff yet.
  final bool changed;

  /// Approved leave that day (`paid` / `sick` / `unpaid`).
  final String? leave;

  /// Worked here that day (joined before / not left yet).
  final bool employed;

  bool get isOff => kind == 'off';

  factory RosterCell.fromJson(Json j) => RosterCell(
    date: asString(j['date']),
    kind: asString(j['kind'], 'shift'),
    shiftId: asStringOrNull(j['shiftId']),
    usual: j['usual'] == null ? true : asBool(j['usual']),
    changed: asBool(j['changed']),
    leave: asStringOrNull(j['leave']),
    employed: j['employed'] == null ? true : asBool(j['employed']),
  );
}

class RosterStaff {
  const RosterStaff({required this.id, required this.name, this.designation, this.cells = const []});
  final String id;
  final String name;
  final String? designation;
  final List<RosterCell> cells;

  RosterCell? cellOn(String date) {
    for (final c in cells) {
      if (c.date == date) return c;
    }
    return null;
  }

  factory RosterStaff.fromJson(Json j) => RosterStaff(
    id: asString(j['id']),
    name: asString(j['name']),
    designation: asStringOrNull(j['designation']),
    cells: asList(j['cells'], RosterCell.fromJson),
  );
}

/// Something to fix before sending: leave on a working day, or no day off all week.
class RosterProblem {
  const RosterProblem({required this.type, required this.employeeId, required this.name, required this.date});
  final String type;
  final String employeeId;
  final String name;
  final String date;

  factory RosterProblem.fromJson(Json j) => RosterProblem(
    type: asString(j['type']),
    employeeId: asString(j['employeeId']),
    name: asString(j['name']),
    date: asString(j['date']),
  );
}

/// "Repeat every week": `same` (next week = this week) or `rotate` (everyone moves to the next shift each week).
class RosterRepeat {
  const RosterRepeat({required this.mode, required this.startWeek, this.autoSend = false, this.staff = 0});
  final String mode;
  final String startWeek;

  /// Sent to staff on its own every Thursday (otherwise owners are reminded).
  final bool autoSend;
  final int staff;

  bool get swaps => mode == 'rotate';

  static RosterRepeat? fromJson(Object? v) {
    final j = asMapOrNull(v);
    if (j == null) return null;
    return RosterRepeat(
      mode: asString(j['mode'], 'same'),
      startWeek: asString(j['startWeek']),
      autoSend: asBool(j['autoSend']),
      staff: asInt(j['staff']),
    );
  }
}

class RosterWeek {
  const RosterWeek({
    required this.weekStart,
    this.days = const [],
    this.shifts = const [],
    this.staff = const [],
    this.notSent = 0,
    this.problems = const [],
    this.repeat,
    this.repeatAllowed = false,
  });
  final String weekStart;
  final List<({String date, String? holiday})> days;
  final List<Shift> shifts;
  final List<RosterStaff> staff;
  final int notSent;
  final List<RosterProblem> problems;
  final RosterRepeat? repeat;

  /// The plan includes "Repeat every week" (Growth and up).
  final bool repeatAllowed;

  Shift? shiftById(String? id) {
    for (final s in shifts) {
      if (s.id == id) return s;
    }
    return null;
  }

  factory RosterWeek.fromJson(Json j) => RosterWeek(
    weekStart: asString(j['weekStart']),
    days: asList(j['days'], (Json d) => (date: asString(d['date']), holiday: asStringOrNull(d['holiday']))),
    shifts: asList(j['shifts'], Shift.fromJson),
    staff: asList(j['staff'], RosterStaff.fromJson),
    notSent: asInt(j['notSent']),
    problems: asList(j['problems'], RosterProblem.fromJson),
    repeat: RosterRepeat.fromJson(j['repeat']),
    repeatAllowed: asBool(j['repeatAllowed']),
  );
}

/// A staff member's own week, as sent.
class MyRosterDay {
  const MyRosterDay({
    required this.date,
    required this.kind,
    this.shiftId,
    this.holiday,
    this.leave,
    this.changed = false,
  });
  final String date;
  final String kind;
  final String? shiftId;
  final String? holiday;
  final String? leave;
  final bool changed;

  factory MyRosterDay.fromJson(Json j) => MyRosterDay(
    date: asString(j['date']),
    kind: asString(j['kind'], 'shift'),
    shiftId: asStringOrNull(j['shiftId']),
    holiday: asStringOrNull(j['holiday']),
    leave: asStringOrNull(j['leave']),
    changed: asBool(j['changed']),
  );
}

class MyRosterWeek {
  const MyRosterWeek({required this.weekStart, this.rostered = false, this.shifts = const [], this.days = const []});
  final String weekStart;

  /// The owner sent a roster for this week (otherwise the home screen skips "My week").
  final bool rostered;
  final List<Shift> shifts;
  final List<MyRosterDay> days;

  Shift? shiftById(String? id) {
    for (final s in shifts) {
      if (s.id == id) return s;
    }
    return null;
  }

  factory MyRosterWeek.fromJson(Json j) => MyRosterWeek(
    weekStart: asString(j['weekStart']),
    rostered: asBool(j['rostered']),
    shifts: asList(j['shifts'], Shift.fromJson),
    days: asList(j['days'], MyRosterDay.fromJson),
  );
}
