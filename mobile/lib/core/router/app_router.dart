import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/accounts/accounts_screen.dart';
import '../../features/accounts/past_payslips_screen.dart';
import '../../features/accounts/recover_screen.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/otp_screen.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/employee/attendance/employee_attendance_screen.dart';
import '../../features/employee/consent/consent_screen.dart';
import '../../features/employee/home/employee_home_screen.dart';
import '../../features/employee/leave/employee_leave_screen.dart';
import '../../features/employee/face/face_setup_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/employee/salary/employee_salary_screen.dart';
import '../../features/employee/shell/employee_shell.dart';
import '../../features/owner/more/accountants_screen.dart';
import '../../features/owner/more/audit_screen.dart';
import '../../features/owner/more/owners_screen.dart';
import '../../features/owner/more/billing_screen.dart';
import '../../features/owner/more/branches_screen.dart';
import '../../features/owner/more/help_screen.dart';
import '../../features/owner/more/holidays_screen.dart';
import '../../features/owner/more/leaves_screen.dart';
import '../../features/owner/more/more_screen.dart';
import '../../features/owner/more/reports_screen.dart';
import '../../features/owner/more/settings_screen.dart';
import '../../features/owner/more/shifts_screen.dart';
import '../../features/owner/more/statutory_screen.dart';
import '../../features/owner/salary/salary_screen.dart';
import '../../features/owner/shell/owner_shell.dart';
import '../../features/owner/staff/add_staff_screen.dart';
import '../../features/owner/staff/staff_list_screen.dart';
import '../../features/owner/staff/staff_profile_screen.dart';
import '../../features/owner/today/today_screen.dart';
import '../../features/setup/setup_screen.dart';
import '../../features/setup/setup_staff_screen.dart';
import 'redirect.dart';
import 'routes.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Bridges Riverpod session changes to go_router's `refreshListenable`.
class _SessionListenable extends ChangeNotifier {
  void notify() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final listenable = _SessionListenable();
  ref.listen(authControllerProvider, (_, _) => listenable.notify());
  ref.onDispose(listenable.dispose);

  GoRoute r(String path, Widget Function(GoRouterState s) build, {List<RouteBase> routes = const []}) =>
      GoRoute(path: path, builder: (_, s) => build(s), routes: routes);

  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.splash,
    refreshListenable: listenable,
    redirect: (context, state) => computeRedirect(ref.read(authControllerProvider), state.matchedLocation),
    routes: [
      r(Routes.splash, (_) => const SplashScreen()),
      r(
        Routes.login,
        (_) => const LoginScreen(),
        routes: [
          GoRoute(
            path: 'otp',
            builder: (_, s) => OtpScreen(
              phone: s.uri.queryParameters['phone'] ?? '',
              devCode: s.uri.queryParameters['devCode'],
              channel: s.uri.queryParameters['channel'] ?? 'sms',
            ),
          ),
        ],
      ),
      r(
        Routes.setup,
        (_) => const SetupScreen(),
        routes: [GoRoute(path: 'staff', builder: (_, _) => const SetupStaffScreen())],
      ),
      r(Routes.employeeConsent, (_) => const ConsentScreen()),
      r(
        Routes.accounts,
        (_) => const AccountsScreen(),
        routes: [
          GoRoute(path: 'new', builder: (_, _) => const SetupScreen(another: true)),
          GoRoute(path: 'recover', builder: (_, _) => const RecoverScreen()),
          GoRoute(path: 'payslips', builder: (_, _) => const PastPayslipsScreen()),
        ],
      ),

      // ---------------------------------------------------------- Owner
      // आज · स्टाफ़ · [Mint] · सैलरी · और — attendance lives in Today.
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => OwnerShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [r(Routes.ownerHome, (_) => const TodayScreen())]),
          StatefulShellBranch(
            routes: [
              r(
                Routes.ownerStaff,
                (_) => const StaffListScreen(),
                routes: [
                  GoRoute(path: 'add', builder: (_, _) => const AddStaffScreen()),
                  GoRoute(
                    path: ':id',
                    builder: (_, s) => StaffProfileScreen(employeeId: s.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(routes: [r(Routes.ownerSalary, (_) => const SalaryScreen())]),
          StatefulShellBranch(
            routes: [
              r(
                Routes.ownerMore,
                (_) => const MoreScreen(),
                routes: [
                  GoRoute(path: 'leaves', builder: (_, _) => const LeavesScreen()),
                  GoRoute(path: 'reports', builder: (_, _) => const ReportsScreen()),
                  GoRoute(
                    path: 'settings',
                    builder: (_, _) => const SettingsScreen(),
                    routes: [
                      GoRoute(path: 'shifts', builder: (_, _) => const ShiftsScreen()),
                      GoRoute(path: 'branches', builder: (_, _) => const BranchesScreen()),
                      GoRoute(path: 'holidays', builder: (_, _) => const HolidaysScreen()),
                      GoRoute(path: 'accountants', builder: (_, _) => const AccountantsScreen()),
                      GoRoute(path: 'owners', builder: (_, _) => const OwnersScreen()),
                      GoRoute(path: 'statutory', builder: (_, _) => const StatutoryScreen()),
                    ],
                  ),
                  GoRoute(path: 'billing', builder: (_, _) => const BillingScreen()),
                  GoRoute(path: 'audit', builder: (_, _) => const AuditScreen()),
                  GoRoute(path: 'help', builder: (_, _) => const HelpScreen()),
                  GoRoute(path: 'profile', builder: (_, _) => const ProfileScreen(showBack: true)),
                ],
              ),
            ],
          ),
        ],
      ),

      // ------------------------------------------------------- Employee
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => EmployeeShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [r(Routes.employeeHome, (_) => const EmployeeHomeScreen())]),
          StatefulShellBranch(routes: [r(Routes.employeeAttendance, (_) => const EmployeeAttendanceScreen())]),
          StatefulShellBranch(routes: [r(Routes.employeeLeave, (_) => const EmployeeLeaveScreen())]),
          StatefulShellBranch(routes: [r(Routes.employeeSalary, (_) => const EmployeeSalaryScreen())]),
          StatefulShellBranch(
            routes: [
              r(
                Routes.employeeProfile,
                (_) => const ProfileScreen(),
                routes: [GoRoute(path: 'face', builder: (_, _) => const FaceSetupScreen())],
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
