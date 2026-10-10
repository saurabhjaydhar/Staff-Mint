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
    this.memberships = const [],
    this.activeMembershipId,
    this.needsAccountChoice = false,
    this.blockedAccounts = const [],
    this.endedNotices = const [],
    this.closedBusinesses = const [],
    this.pendingTransfers = const [],
    this.recoveryHolds = const [],
    this.notice,
  });

  const SessionState.unknown({this.restoreFailed = false})
    : status = SessionStatus.unknown,
      user = null,
      company = null,
      employee = null,
      needsCompanySetup = false,
      memberships = const [],
      activeMembershipId = null,
      needsAccountChoice = false,
      blockedAccounts = const [],
      endedNotices = const [],
      closedBusinesses = const [],
      pendingTransfers = const [],
      recoveryHolds = const [],
      notice = null;

  const SessionState.unauthenticated()
    : status = SessionStatus.unauthenticated,
      user = null,
      company = null,
      employee = null,
      needsCompanySetup = false,
      restoreFailed = false,
      memberships = const [],
      activeMembershipId = null,
      needsAccountChoice = false,
      blockedAccounts = const [],
      endedNotices = const [],
      closedBusinesses = const [],
      pendingTransfers = const [],
      recoveryHolds = const [],
      notice = null;

  final SessionStatus status;
  final User? user;
  final Company? company;
  final Employee? employee;
  final bool needsCompanySetup;

  /// Tokens exist but neither the network nor the cache could identify the
  /// user (first start offline). The splash screen offers a retry.
  final bool restoreFailed;

  /// Every business this number can open (owner here, staff there…).
  final List<Membership> memberships;

  /// The one this device is in.
  final String? activeMembershipId;

  /// Just logged in with more than one account: show the chooser first.
  final bool needsAccountChoice;

  /// Staff accounts locked to another phone (offer "Request this phone").
  final List<Membership> blockedAccounts;

  /// "Your access to X ended" notices not yet dismissed.
  final List<EndedNotice> endedNotices;

  /// Businesses this person closed that can still be restored.
  final List<ClosedBusiness> closedBusinesses;

  /// Offers to become main owner of a business.
  final List<TransferOffer> pendingTransfers;

  /// Support recoveries in their hold that this person can stop.
  final List<RecoveryHold> recoveryHolds;

  /// Shown once as a snackbar after the account changed under this phone.
  final AccountChange? notice;

  bool get hasManyAccounts => memberships.length > 1;
  Membership? get activeMembership {
    for (final m in memberships) {
      if (m.id == activeMembershipId) return m;
    }
    return null;
  }

  bool get isAuthenticated => status == SessionStatus.authenticated;
  String? get role => user?.role;
  bool get isEmployee => user?.isEmployee ?? false;
  bool get isOwner => user?.isOwner ?? false;

  /// Employees must accept the location notice before first check-in.
  bool get needsConsent => isEmployee && employee != null && !employee!.locationConsent;

  SessionState copyWith({
    User? user,
    Company? company,
    Employee? employee,
    bool? needsCompanySetup,
    List<Membership>? memberships,
    String? activeMembershipId,
    bool? needsAccountChoice,
    List<Membership>? blockedAccounts,
    List<EndedNotice>? endedNotices,
    List<ClosedBusiness>? closedBusinesses,
    List<TransferOffer>? pendingTransfers,
    List<RecoveryHold>? recoveryHolds,
    AccountChange? notice,
    bool clearNotice = false,
  }) => SessionState(
    status: status,
    user: user ?? this.user,
    company: company ?? this.company,
    employee: employee ?? this.employee,
    needsCompanySetup: needsCompanySetup ?? this.needsCompanySetup,
    memberships: memberships ?? this.memberships,
    activeMembershipId: activeMembershipId ?? this.activeMembershipId,
    needsAccountChoice: needsAccountChoice ?? this.needsAccountChoice,
    blockedAccounts: blockedAccounts ?? this.blockedAccounts,
    endedNotices: endedNotices ?? this.endedNotices,
    closedBusinesses: closedBusinesses ?? this.closedBusinesses,
    pendingTransfers: pendingTransfers ?? this.pendingTransfers,
    recoveryHolds: recoveryHolds ?? this.recoveryHolds,
    notice: clearNotice ? null : (notice ?? this.notice),
  );
}
