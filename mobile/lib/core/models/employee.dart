import '../utils/json.dart';
import 'leave.dart';

class Employee {
  const Employee({
    required this.id,
    required this.name,
    required this.phone,
    this.branchId,
    this.shiftId,
    this.wageType = 'monthly',
    this.ratePaise = 0,
    this.designation,
    this.joiningDate,
    this.status = 'active',
    this.locationConsent = false,
    this.consentAt,
    this.hasDevice = false,
    this.language = 'en',
    this.leaveBalance,
    this.advanceBalancePaise,
  });

  final String id;
  final String name;
  final String phone;
  final String? branchId;
  final String? shiftId;
  final String wageType;
  final int ratePaise;
  final String? designation;
  final String? joiningDate;
  final String status;
  final bool locationConsent;
  final String? consentAt;
  final bool hasDevice;
  final String language;

  /// Present only on `GET /employees/:id`.
  final LeaveBalance? leaveBalance;
  final int? advanceBalancePaise;

  bool get isActive => status == 'active';
  bool get isDaily => wageType == 'daily';

  factory Employee.fromJson(Json j) {
    final consent = asMap(j['consent']);
    return Employee(
      id: asString(j['id']),
      name: asString(j['name']),
      phone: asString(j['phone']),
      branchId: asStringOrNull(j['branchId']),
      shiftId: asStringOrNull(j['shiftId']),
      wageType: asString(j['wageType'], 'monthly'),
      ratePaise: asInt(j['ratePaise']),
      designation: asStringOrNull(j['designation']),
      joiningDate: asStringOrNull(j['joiningDate']),
      status: asString(j['status'], 'active'),
      locationConsent: asBool(consent['location']),
      consentAt: asStringOrNull(consent['at']),
      hasDevice: asBool(j['hasDevice']),
      language: asString(j['language'], 'en'),
      leaveBalance: j['leaveBalance'] is Map ? LeaveBalance.fromJson(asMap(j['leaveBalance'])) : null,
      advanceBalancePaise: asIntOrNull(j['advanceBalancePaise']),
    );
  }
}

/// Short employee reference embedded in day rows / month grids.
class EmployeeRef {
  const EmployeeRef({required this.id, required this.name, this.phone, this.designation});
  final String id;
  final String name;
  final String? phone;
  final String? designation;

  factory EmployeeRef.fromJson(Json j) => EmployeeRef(
    id: asString(j['id']),
    name: asString(j['name']),
    phone: asStringOrNull(j['phone']),
    designation: asStringOrNull(j['designation']),
  );
}

/// Input row for `POST /employees` and `/employees/bulk`.
class NewEmployee {
  const NewEmployee({
    required this.name,
    required this.phone,
    this.wageType,
    this.ratePaise,
    this.designation,
    this.shiftId,
    this.branchId,
    this.joiningDate,
  });
  final String name;
  final String phone;
  final String? wageType;
  final int? ratePaise;
  final String? designation;
  final String? shiftId;
  final String? branchId;
  final String? joiningDate;

  Json toJson() => {
    'name': name,
    'phone': phone,
    'wageType': ?wageType,
    'ratePaise': ?ratePaise,
    if (designation != null && designation!.isNotEmpty) 'designation': designation,
    'shiftId': ?shiftId,
    'branchId': ?branchId,
    'joiningDate': ?joiningDate,
  };
}
