import '../../features/auth/session_state.dart';
import 'routes.dart';

/// Pure routing decision so it can be unit-tested without widgets.
///
/// Returns the location to redirect to, or null to stay on [location].
String? computeRedirect(SessionState session, String location) {
  bool at(String path) => location == path;
  bool under(String prefix) => location == prefix || location.startsWith('$prefix/');

  switch (session.status) {
    case SessionStatus.unknown:
      return at(Routes.splash) ? null : Routes.splash;
    case SessionStatus.unauthenticated:
      return under(Routes.login) ? null : Routes.login;
    case SessionStatus.authenticated:
      break;
  }

  // Several businesses on one number: pick one before anything else.
  if (session.needsAccountChoice) {
    return under(Routes.accounts) ? null : Routes.accounts;
  }

  if (session.needsCompanySetup) {
    return at(Routes.setup) ? null : Routes.setup;
  }

  // The chooser and "new business" are open to every role.
  if (under(Routes.accounts)) return null;

  if (session.isEmployee) {
    if (session.needsConsent) {
      return at(Routes.employeeConsent) ? null : Routes.employeeConsent;
    }
    final allowed = location.startsWith('/employee/') && !at(Routes.employeeConsent);
    return allowed ? null : Routes.employeeHome;
  }

  // owner / manager / ca → owner shell. The staff step of the setup flow runs
  // right after the company is created, so it stays reachable (and /setup
  // forwards there once the company exists).
  if (at(Routes.setup)) return Routes.setupStaff;
  final allowed = location.startsWith('/owner/') || at(Routes.setupStaff);
  return allowed ? null : Routes.ownerHome;
}
