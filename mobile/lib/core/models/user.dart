import '../utils/json.dart';

class UserRole {
  UserRole._();
  static const owner = 'owner';
  static const manager = 'manager';
  static const employee = 'employee';
  static const ca = 'ca';
}

class User {
  const User({
    required this.id,
    required this.phone,
    required this.name,
    required this.role,
    this.companyId,
    this.employeeId,
    this.language = 'en',
  });

  final String id;
  final String phone;
  final String name;
  final String role;
  final String? companyId;
  final String? employeeId;
  final String language;

  bool get isEmployee => role == UserRole.employee;
  bool get isOwner => role == UserRole.owner;
  bool get isAdmin => role == UserRole.owner || role == UserRole.manager || role == UserRole.ca;

  factory User.fromJson(Json j) => User(
    id: asString(j['id']),
    phone: asString(j['phone']),
    name: asString(j['name']),
    role: asString(j['role'], UserRole.owner),
    companyId: asStringOrNull(j['companyId']),
    employeeId: asStringOrNull(j['employeeId']),
    language: asString(j['language'], 'en'),
  );

  Json toJson() => {
    'id': id,
    'phone': phone,
    'name': name,
    'role': role,
    'companyId': companyId,
    'employeeId': employeeId,
    'language': language,
  };

  User copyWith({String? name, String? language, String? companyId}) => User(
    id: id,
    phone: phone,
    name: name ?? this.name,
    role: role,
    companyId: companyId ?? this.companyId,
    employeeId: employeeId,
    language: language ?? this.language,
  );
}
