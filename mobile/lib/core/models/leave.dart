import '../utils/json.dart';

class Leave {
  const Leave({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.type,
    required this.from,
    required this.to,
    required this.days,
    this.halfDay = false,
    this.reason,
    this.status = 'pending',
    this.decidedAt,
    this.note,
    this.balanceLeft,
    this.balanceAfter,
  });

  final String id;
  final String employeeId;
  final String employeeName;
  final String type;
  final String from;
  final String to;
  final num days;
  final bool halfDay;
  final String? reason;
  final String status;
  final String? decidedAt;
  final String? note;

  /// Paid/sick leaves left before and after approving this request (owner's approval card).
  final num? balanceLeft;
  final num? balanceAfter;

  bool get isPending => status == 'pending';

  factory Leave.fromJson(Json j) => Leave(
    id: asString(j['id']),
    employeeId: asString(j['employeeId']),
    employeeName: asString(j['employeeName']),
    type: asString(j['type'], 'paid'),
    from: asString(j['from']),
    to: asString(j['to']),
    days: asNum(j['days'], 1),
    halfDay: asBool(j['halfDay']),
    reason: asStringOrNull(j['reason']),
    status: asString(j['status'], 'pending'),
    decidedAt: asStringOrNull(j['decidedAt']),
    note: asStringOrNull(j['note']),
    balanceLeft: j['balance'] is Map ? asNum(asMap(j['balance'])['left']) : null,
    balanceAfter: j['balance'] is Map ? asNum(asMap(j['balance'])['after']) : null,
  );
}

class LeaveBalance {
  const LeaveBalance({
    required this.employeeId,
    required this.year,
    this.paid = 0,
    this.sick = 0,
    this.usedPaid = 0,
    this.usedSick = 0,
  });
  final String employeeId;
  final int year;
  final num paid;
  final num sick;
  final num usedPaid;
  final num usedSick;

  num get paidLeft => paid - usedPaid;
  num get sickLeft => sick - usedSick;

  factory LeaveBalance.fromJson(Json j) => LeaveBalance(
    employeeId: asString(j['employeeId']),
    year: asInt(j['year'], DateTime.now().year),
    paid: asNum(j['paid'], 0),
    sick: asNum(j['sick'], 0),
    usedPaid: asNum(j['usedPaid'], 0),
    usedSick: asNum(j['usedSick'], 0),
  );
}
