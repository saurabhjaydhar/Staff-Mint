import '../utils/json.dart';

/// Salary account, always masked by the server (last 4 digits only).
class BankInfo {
  const BankInfo({required this.holderName, this.accountLast4, this.ifsc, this.upiId, this.updatedAt});
  final String holderName;
  final String? accountLast4;
  final String? ifsc;
  final String? upiId;
  final DateTime? updatedAt;

  bool get hasAccount => accountLast4 != null;

  static BankInfo? fromJsonOrNull(Object? v) => v is Map
      ? BankInfo(
          holderName: asString(v['holderName']),
          accountLast4: asStringOrNull(v['accountLast4']),
          ifsc: asStringOrNull(v['ifsc']),
          upiId: asStringOrNull(v['upiId']),
          updatedAt: asDateTimeOrNull(v['updatedAt']),
        )
      : null;
}

class EmergencyContact {
  const EmergencyContact({required this.name, this.phone, this.relation});
  final String name;
  final String? phone;
  final String? relation;

  static EmergencyContact? fromJsonOrNull(Object? v) => v is Map
      ? EmergencyContact(
          name: asString(v['name']),
          phone: asStringOrNull(v['phone']),
          relation: asStringOrNull(v['relation']),
        )
      : null;

  Json toJson() => {'name': name, 'phone': phone, 'relation': relation};
}

class WorkInfo {
  const WorkInfo({
    required this.employeeId,
    this.designation,
    this.joiningDate,
    this.wageType = 'monthly',
    this.ratePaise = 0,
    this.branchName,
    this.shiftName,
    this.shiftStart,
    this.shiftEnd,
  });
  final String employeeId;
  final String? designation;
  final String? joiningDate;
  final String wageType;
  final int ratePaise;
  final String? branchName;
  final String? shiftName;
  final String? shiftStart;
  final String? shiftEnd;

  factory WorkInfo.fromJson(Json j) {
    final shift = asMap(j['shift']);
    return WorkInfo(
      employeeId: asString(j['employeeId']),
      designation: asStringOrNull(j['designation']),
      joiningDate: asStringOrNull(j['joiningDate']),
      wageType: asString(j['wageType'], 'monthly'),
      ratePaise: asInt(j['ratePaise']),
      branchName: asStringOrNull(j['branchName']),
      shiftName: asStringOrNull(shift['name']),
      shiftStart: asStringOrNull(shift['start']),
      shiftEnd: asStringOrNull(shift['end']),
    );
  }
}

/// `GET /me/profile`.
class Profile {
  const Profile({
    required this.userId,
    required this.name,
    required this.phone,
    required this.role,
    this.email,
    this.language = 'hi',
    this.photoUrl,
    this.memberSince,
    this.companyName,
    this.businessType,
    this.planName,
    this.work,
    this.bank,
    this.emergencyContact,
    this.completePercent = 0,
    this.missing = const [],
  });

  final String userId;
  final String name;
  final String phone;
  final String role;
  final String? email;
  final String language;
  final String? photoUrl;
  final DateTime? memberSince;
  final String? companyName;
  final String? businessType;
  final String? planName;
  final WorkInfo? work;
  final BankInfo? bank;
  final EmergencyContact? emergencyContact;
  final int completePercent;

  /// photo | name | email | bank | emergencyContact
  final List<String> missing;

  bool get isStaff => work != null;

  factory Profile.fromJson(Json j) {
    final u = asMap(j['user']);
    final c = asMapOrNull(j['company']);
    final done = asMap(j['completeness']);
    return Profile(
      userId: asString(u['id']),
      name: asString(u['name']),
      phone: asString(u['phone']),
      role: asString(u['role'], 'owner'),
      email: asStringOrNull(u['email']),
      language: asString(u['language'], 'hi'),
      photoUrl: asStringOrNull(u['photoUrl']),
      memberSince: asDateTimeOrNull(u['memberSince']),
      companyName: c == null ? null : asStringOrNull(c['name']),
      businessType: c == null ? null : asStringOrNull(c['businessType']),
      planName: c == null ? null : asStringOrNull(c['planName']),
      work: j['work'] is Map ? WorkInfo.fromJson(asMap(j['work'])) : null,
      bank: BankInfo.fromJsonOrNull(j['bank']),
      emergencyContact: EmergencyContact.fromJsonOrNull(j['emergencyContact']),
      completePercent: asInt(done['percent']),
      missing: asStringList(done['missing']),
    );
  }
}
