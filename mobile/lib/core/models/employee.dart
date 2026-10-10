import '../utils/json.dart';
import 'leave.dart';
import 'profile.dart';

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
    this.faceStatus = 'none',
    this.hasDevice = false,
    this.linked = false,
    this.invitedAt,
    this.language = 'en',
    this.leaveBalance,
    this.advanceBalancePaise,
    this.bank,
    this.emergencyContact,
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

  /// Face check photo: none | pending (owner to approve) | approved.
  final String faceStatus;
  final bool hasDevice;

  /// Has opened StaffMint for this business; when the app invite was last sent.
  final bool linked;
  final DateTime? invitedAt;
  final String language;

  /// Present only on `GET /employees/:id`.
  final LeaveBalance? leaveBalance;
  final int? advanceBalancePaise;
  final BankInfo? bank;
  final EmergencyContact? emergencyContact;

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
      faceStatus: asString(asMap(j['face'])['status'], 'none'),
      hasDevice: asBool(j['hasDevice']),
      linked: asBool(j['linked']),
      invitedAt: asDateTimeOrNull(j['invitedAt']),
      language: asString(j['language'], 'en'),
      leaveBalance: j['leaveBalance'] is Map ? LeaveBalance.fromJson(asMap(j['leaveBalance'])) : null,
      advanceBalancePaise: asIntOrNull(j['advanceBalancePaise']),
      bank: BankInfo.fromJsonOrNull(j['bank']),
      emergencyContact: EmergencyContact.fromJsonOrNull(j['emergencyContact']),
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

/// A staff member's face check photo (`/me/face`, `/employees/:id/face`).
class FaceInfo {
  const FaceInfo({this.status = 'none', this.photoUrl, this.enrolledAt, this.approvedAt});
  final String status; // none | pending | approved
  final String? photoUrl;
  final DateTime? enrolledAt;
  final DateTime? approvedAt;

  bool get isNone => status == 'none';
  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';

  factory FaceInfo.fromJson(Json j) => FaceInfo(
    status: asString(j['status'], 'none'),
    photoUrl: asStringOrNull(j['photoUrl']),
    enrolledAt: asDateTimeOrNull(j['enrolledAt']),
    approvedAt: asDateTimeOrNull(j['approvedAt']),
  );
}

/// A face photo waiting for the owner (dashboard "needs you").
class FaceEnrollment {
  const FaceEnrollment({required this.employeeId, required this.employeeName, required this.face});
  final String employeeId;
  final String employeeName;
  final FaceInfo face;

  factory FaceEnrollment.fromJson(Json j) => FaceEnrollment(
    employeeId: asString(j['employeeId']),
    employeeName: asString(j['employeeName']),
    face: FaceInfo.fromJson(j),
  );
}
