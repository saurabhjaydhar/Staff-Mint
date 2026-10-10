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
  });

  final String id;
  final String companyId;
  final String companyName;
  final String role;
  final String? businessType;
  final DateTime? lastUsedAt;

  bool get isStaff => role == 'employee' || role == 'manager';

  factory Membership.fromJson(Json j) => Membership(
    id: asString(j['id']),
    companyId: asString(j['companyId']),
    companyName: asString(j['companyName']),
    role: asString(j['role'], 'employee'),
    businessType: asStringOrNull(j['businessType']),
    lastUsedAt: asDateTimeOrNull(j['lastUsedAt']),
  );
}
