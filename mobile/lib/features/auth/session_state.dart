import '../../core/models/models.dart';

enum SessionStatus { unknown, unauthenticated, authenticated }

/// Who is logged in and what the router should show.
class SessionState {
  const SessionState({
    required this.status,
    this.user,
    this.company,
    this.employee,
    this.needsCompanySetup = false,
    this.restoreFailed = false,
  });

  const SessionState.unknown({this.restoreFailed = false})
    : status = SessionStatus.unknown,
      user = null,
      company = null,
      employee = null,
      needsCompanySetup = false;

  const SessionState.unauthenticated()
    : status = SessionStatus.unauthenticated,
      user = null,
      company = null,
      employee = null,
      needsCompanySetup = false,
      restoreFailed = false;

  final SessionStatus status;
  final User? user;
  final Company? company;
  final Employee? employee;
  final bool needsCompanySetup;

  /// Tokens exist but neither the network nor the cache could identify the
  /// user (first start offline). The splash screen offers a retry.
  final bool restoreFailed;

  bool get isAuthenticated => status == SessionStatus.authenticated;
  String? get role => user?.role;
  bool get isEmployee => user?.isEmployee ?? false;
  bool get isOwner => user?.isOwner ?? false;

  /// Employees must accept the location notice before first check-in.
  bool get needsConsent => isEmployee && employee != null && !employee!.locationConsent;

  SessionState copyWith({User? user, Company? company, Employee? employee, bool? needsCompanySetup}) => SessionState(
    status: status,
    user: user ?? this.user,
    company: company ?? this.company,
    employee: employee ?? this.employee,
    needsCompanySetup: needsCompanySetup ?? this.needsCompanySetup,
  );
}
