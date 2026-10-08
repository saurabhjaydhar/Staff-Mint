import '../utils/json.dart';

class Advance {
  const Advance({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.amountPaise,
    required this.date,
    this.mode = 'installments',
    this.installments = 1,
    this.installmentPaise = 0,
    this.repaidPaise = 0,
    this.balancePaise = 0,
    this.status = 'active',
    this.skipMonths = const [],
    this.note,
  });

  final String id;
  final String employeeId;
  final String employeeName;
  final int amountPaise;
  final String date;
  final String mode;
  final int installments;
  final int installmentPaise;
  final int repaidPaise;
  final int balancePaise;
  final String status;
  final List<String> skipMonths;
  final String? note;

  bool get isActive => status == 'active';

  factory Advance.fromJson(Json j) => Advance(
    id: asString(j['id']),
    employeeId: asString(j['employeeId']),
    employeeName: asString(j['employeeName']),
    amountPaise: asInt(j['amountPaise']),
    date: asString(j['date']),
    mode: asString(j['mode'], 'installments'),
    installments: asInt(j['installments'], 1),
    installmentPaise: asInt(j['installmentPaise']),
    repaidPaise: asInt(j['repaidPaise']),
    balancePaise: asInt(j['balancePaise']),
    status: asString(j['status'], 'active'),
    skipMonths: asStringList(j['skipMonths']),
    note: asStringOrNull(j['note']),
  );
}

class Adjustment {
  const Adjustment({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.month,
    required this.type,
    required this.amountPaise,
    this.note,
  });
  final String id;
  final String employeeId;
  final String employeeName;
  final String month;
  final String type; // bonus | deduction
  final int amountPaise;
  final String? note;

  bool get isBonus => type == 'bonus';

  factory Adjustment.fromJson(Json j) => Adjustment(
    id: asString(j['id']),
    employeeId: asString(j['employeeId']),
    employeeName: asString(j['employeeName']),
    month: asString(j['month']),
    type: asString(j['type'], 'bonus'),
    amountPaise: asInt(j['amountPaise']),
    note: asStringOrNull(j['note']),
  );
}
