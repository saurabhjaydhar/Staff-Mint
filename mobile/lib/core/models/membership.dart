import '../utils/json.dart';

/// One business this person can open: owner of one, staff at another,
/// accountant of a third. Each device is in one membership at a time.
class Membership {
  const Membership({
    required this.id,
    required this.companyId,
    required this.companyName,
    required this.role,
    this.businessType,
    this.lastUsedAt,
    this.lockedToOtherPhone = false,
  });

  final String id;
  final String companyId;
  final String companyName;
  final String role;
  final String? businessType;
  final DateTime? lastUsedAt;

  /// Staff account bound to another phone: offer "Request this phone".
  final bool lockedToOtherPhone;

  bool get isStaff => role == 'employee' || role == 'manager';

  factory Membership.fromJson(Json j) => Membership(
    id: asString(j['id']),
    companyId: asString(j['companyId']),
    companyName: asString(j['companyName']),
    role: asString(j['role'], 'employee'),
    businessType: asStringOrNull(j['businessType']),
    lastUsedAt: asDateTimeOrNull(j['lastUsedAt']),
    lockedToOtherPhone: asBool(j['lockedToOtherPhone']),
  );
}

/// "Your access to Gupta Sweets ended on 3 Oct" — until dismissed.
class EndedNotice {
  const EndedNotice({required this.id, required this.companyName, this.endedAt, this.reason});
  final String id;
  final String companyName;
  final DateTime? endedAt;

  /// removed | closed | phone_changed | import_rollback
  final String? reason;

  factory EndedNotice.fromJson(Json j) => EndedNotice(
    id: asString(j['id']),
    companyName: asString(j['companyName']),
    endedAt: asDateTimeOrNull(j['endedAt']),
    reason: asStringOrNull(j['endedReason']),
  );
}

/// A business this person closed that can still be restored.
class ClosedBusiness {
  const ClosedBusiness({required this.companyId, required this.companyName, this.businessType, this.restoreUntil});
  final String companyId;
  final String companyName;
  final String? businessType;
  final DateTime? restoreUntil;

  factory ClosedBusiness.fromJson(Json j) => ClosedBusiness(
    companyId: asString(j['companyId']),
    companyName: asString(j['companyName']),
    businessType: asStringOrNull(j['businessType']),
    restoreUntil: asDateTimeOrNull(j['restoreUntil']),
  );
}

/// Sent with a token refresh when this phone's account ended or its role changed.
class AccountChange {
  const AccountChange({required this.kind, this.reason, this.companyName = '', this.role});
  final String kind; // ended | role_changed
  final String? reason;
  final String companyName;
  final String? role;

  bool get ended => kind == 'ended';

  factory AccountChange.fromJson(Json j) => AccountChange(
    kind: asString(j['kind'], 'ended'),
    reason: asStringOrNull(j['reason']),
    companyName: asString(j['companyName']),
    role: asStringOrNull(j['role']),
  );
}

/// Staff asking to use a new phone (owner's Needs-you).
class DeviceRequestItem {
  const DeviceRequestItem({required this.id, required this.employeeName, this.employeeId, this.deviceName});
  final String id;
  final String? employeeId;
  final String employeeName;
  final String? deviceName;

  factory DeviceRequestItem.fromJson(Json j) => DeviceRequestItem(
    id: asString(j['id']),
    employeeId: asStringOrNull(j['employeeId']),
    employeeName: asString(j['employeeName']),
    deviceName: asStringOrNull(j['deviceName']),
  );
}

class Accountant {
  const Accountant({required this.id, required this.name, required this.phone});
  final String id;
  final String name;
  final String phone;

  factory Accountant.fromJson(Json j) =>
      Accountant(id: asString(j['id']), name: asString(j['name']), phone: asString(j['phone']));
}
