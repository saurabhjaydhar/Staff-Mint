import '../utils/json.dart';

class PayslipLine {
  const PayslipLine({
    required this.code,
    required this.kind,
    required this.label,
    required this.amountPaise,
    this.explanation = '',
  });
  final String code;
  final String kind; // earning | deduction
  final String label;
  final int amountPaise;
  final String explanation;

  bool get isDeduction => kind == 'deduction';

  factory PayslipLine.fromJson(Json j) => PayslipLine(
    code: asString(j['code']),
    kind: asString(j['kind'], 'earning'),
    label: asString(j['label']),
    amountPaise: asInt(j['amountPaise']),
    explanation: asString(j['explanation']),
  );
}

class PayslipSummary {
  const PayslipSummary({
    this.present = 0,
    this.halfDay = 0,
    this.absent = 0,
    this.paidLeave = 0,
    this.unpaidLeave = 0,
    this.holidays = 0,
    this.weekOffs = 0,
    this.unmarked = 0,
  });
  final num present;
  final num halfDay;
  final num absent;
  final num paidLeave;
  final num unpaidLeave;
  final num holidays;
  final num weekOffs;
  final num unmarked;

  factory PayslipSummary.fromJson(Json j) => PayslipSummary(
    present: asNum(j['present']),
    halfDay: asNum(j['halfDay']),
    absent: asNum(j['absent']),
    paidLeave: asNum(j['paidLeave']),
    unpaidLeave: asNum(j['unpaidLeave']),
    holidays: asNum(j['holidays']),
    weekOffs: asNum(j['weekOffs']),
    unmarked: asNum(j['unmarked']),
  );
}

class Payslip {
  const Payslip({
    required this.id,
    this.runId,
    required this.employeeId,
    required this.employeeName,
    required this.month,
    this.revision = 1,
    this.wageType = 'monthly',
    this.ratePaise = 0,
    this.payableDays = 0,
    this.daysInMonth = 30,
    this.divisor = 30,
    this.summary = const PayslipSummary(),
    this.lines = const [],
    this.grossPaise = 0,
    this.deductionsPaise = 0,
    this.netPaise = 0,
    this.status = 'draft',
    this.pdfUrl,
    this.sentAt,
  });

  final String id;
  final String? runId;
  final String employeeId;
  final String employeeName;
  final String month;
  final int revision;
  final String wageType;
  final int ratePaise;
  final num payableDays;
  final int daysInMonth;
  final num divisor;
  final PayslipSummary summary;
  final List<PayslipLine> lines;
  final int grossPaise;
  final int deductionsPaise;
  final int netPaise;
  final String status;
  final String? pdfUrl;
  final String? sentAt;

  bool get isPersisted => id.isNotEmpty;

  factory Payslip.fromJson(Json j) => Payslip(
    id: asString(j['id']),
    runId: asStringOrNull(j['runId']),
    employeeId: asString(j['employeeId']),
    employeeName: asString(j['employeeName']),
    month: asString(j['month']),
    revision: asInt(j['revision'], 1),
    wageType: asString(j['wageType'], 'monthly'),
    ratePaise: asInt(j['ratePaise']),
    payableDays: asNum(j['payableDays']),
    daysInMonth: asInt(j['daysInMonth'], 30),
    divisor: asNum(j['divisor'], 30),
    summary: PayslipSummary.fromJson(asMap(j['summary'])),
    lines: asList(j['lines'], PayslipLine.fromJson),
    grossPaise: asInt(j['grossPaise']),
    deductionsPaise: asInt(j['deductionsPaise']),
    netPaise: asInt(j['netPaise']),
    status: asString(j['status'], 'draft'),
    pdfUrl: asStringOrNull(j['pdfUrl']),
    sentAt: asStringOrNull(j['sentAt']),
  );
}

class PayrollAnomaly {
  const PayrollAnomaly({
    required this.employeeId,
    required this.employeeName,
    required this.code,
    required this.message,
  });
  final String employeeId;
  final String employeeName;
  final String code;
  final String message;

  factory PayrollAnomaly.fromJson(Json j) => PayrollAnomaly(
    employeeId: asString(j['employeeId']),
    employeeName: asString(j['employeeName']),
    code: asString(j['code']),
    message: asString(j['message']),
  );
}

class PayrollRun {
  const PayrollRun({
    required this.id,
    required this.month,
    this.revision = 1,
    this.status = 'draft',
    this.engineVersion,
    this.grossPaise = 0,
    this.deductionsPaise = 0,
    this.netPaise = 0,
    this.employees = 0,
    this.anomalies = const [],
    this.approvedAt,
    this.paidAt,
    this.payslips,
  });

  final String id;
  final String month;
  final int revision;
  final String status; // draft | approved | paid | superseded
  final String? engineVersion;
  final int grossPaise;
  final int deductionsPaise;
  final int netPaise;
  final int employees;
  final List<PayrollAnomaly> anomalies;
  final String? approvedAt;
  final String? paidAt;
  final List<Payslip>? payslips;

  bool get isDraft => status == 'draft';
  bool get isApproved => status == 'approved';
  bool get isPaid => status == 'paid';

  List<PayrollAnomaly> anomaliesFor(String employeeId) => anomalies.where((a) => a.employeeId == employeeId).toList();

  factory PayrollRun.fromJson(Json j) {
    final totals = asMap(j['totals']);
    return PayrollRun(
      id: asString(j['id']),
      month: asString(j['month']),
      revision: asInt(j['revision'], 1),
      status: asString(j['status'], 'draft'),
      engineVersion: asStringOrNull(j['engineVersion']),
      grossPaise: asInt(totals['grossPaise']),
      deductionsPaise: asInt(totals['deductionsPaise']),
      netPaise: asInt(totals['netPaise']),
      employees: asInt(totals['employees']),
      anomalies: asList(j['anomalies'], PayrollAnomaly.fromJson),
      approvedAt: asStringOrNull(j['approvedAt']),
      paidAt: asStringOrNull(j['paidAt']),
      payslips: j['payslips'] is List ? asList(j['payslips'], Payslip.fromJson) : null,
    );
  }
}

class SalaryOverview {
  const SalaryOverview({this.estimate, this.advanceBalancePaise = 0, this.payslips = const []});
  final Payslip? estimate;
  final int advanceBalancePaise;
  final List<Payslip> payslips;

  factory SalaryOverview.fromJson(Json j) => SalaryOverview(
    estimate: j['estimate'] is Map ? Payslip.fromJson(asMap(j['estimate'])) : null,
    advanceBalancePaise: asInt(j['advanceBalancePaise']),
    payslips: asList(j['payslips'], Payslip.fromJson),
  );
}

class PayslipExplanation {
  const PayslipExplanation({required this.text, this.lines = const []});
  final String text;
  final List<String> lines;

  factory PayslipExplanation.fromJson(Json j) =>
      PayslipExplanation(text: asString(j['text']), lines: asStringList(j['lines']));
}
