import '../utils/json.dart';

/// The shop's PF / ESI / Professional Tax settings (all off for most small shops).
class StatutorySettings {
  const StatutorySettings({
    this.pfEnabled = false,
    this.pfNumber,
    this.basicPercent = 50,
    this.pfRatePercent = 12,
    this.pfWageCeilingPaise = 1500000,
    this.pfCapAtCeiling = true,
    this.esiEnabled = false,
    this.esiNumber,
    this.esiEmployeePercent = 0.75,
    this.esiEmployerPercent = 3.25,
    this.esiWageLimitPaise = 2100000,
    this.ptEnabled = false,
    this.ptState,
    this.ptMonthlyPaise = 20000,
    this.ptMinGrossPaise = 0,
  });

  final bool pfEnabled;
  final String? pfNumber;
  final int basicPercent;
  final num pfRatePercent;
  final int pfWageCeilingPaise;
  final bool pfCapAtCeiling;
  final bool esiEnabled;
  final String? esiNumber;
  final num esiEmployeePercent;
  final num esiEmployerPercent;
  final int esiWageLimitPaise;
  final bool ptEnabled;
  final String? ptState;
  final int ptMonthlyPaise;
  final int ptMinGrossPaise;

  factory StatutorySettings.fromJson(Json j) => StatutorySettings(
    pfEnabled: asBool(j['pfEnabled']),
    pfNumber: asStringOrNull(j['pfNumber']),
    basicPercent: asInt(j['basicPercent'], 50),
    pfRatePercent: asNum(j['pfRatePercent'], 12),
    pfWageCeilingPaise: asInt(j['pfWageCeilingPaise'], 1500000),
    pfCapAtCeiling: j['pfCapAtCeiling'] is bool ? j['pfCapAtCeiling'] as bool : true,
    esiEnabled: asBool(j['esiEnabled']),
    esiNumber: asStringOrNull(j['esiNumber']),
    esiEmployeePercent: asNum(j['esiEmployeePercent'], 0.75),
    esiEmployerPercent: asNum(j['esiEmployerPercent'], 3.25),
    esiWageLimitPaise: asInt(j['esiWageLimitPaise'], 2100000),
    ptEnabled: asBool(j['ptEnabled']),
    ptState: asStringOrNull(j['ptState']),
    ptMonthlyPaise: asInt(j['ptMonthlyPaise'], 20000),
    ptMinGrossPaise: asInt(j['ptMinGrossPaise']),
  );
}

/// What a staff member's salary slip shows besides name and phone. PAN comes back masked.
class EmployeeStatutory {
  const EmployeeStatutory({
    this.employeeCode,
    this.uan,
    this.esicNumber,
    this.panMasked,
    this.pfExempt = false,
    this.esiExempt = false,
  });
  final String? employeeCode;
  final String? uan;
  final String? esicNumber;
  final String? panMasked;
  final bool pfExempt;
  final bool esiExempt;

  bool get isEmpty =>
      employeeCode == null && uan == null && esicNumber == null && panMasked == null && !pfExempt && !esiExempt;

  static EmployeeStatutory? fromJsonOrNull(Object? j) => j is Map ? EmployeeStatutory.fromJson(asMap(j)) : null;

  factory EmployeeStatutory.fromJson(Json j) => EmployeeStatutory(
    employeeCode: asStringOrNull(j['employeeCode']),
    uan: asStringOrNull(j['uan']),
    esicNumber: asStringOrNull(j['esicNumber']),
    panMasked: asStringOrNull(j['panMasked']),
    pfExempt: asBool(j['pfExempt']),
    esiExempt: asBool(j['esiExempt']),
  );
}
