import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/core/router/routes.dart';
import 'package:staffmint/core/storage/providers.dart';
import 'package:staffmint/features/accounts/accounts_screen.dart';
import 'package:staffmint/features/auth/auth_controller.dart';
import 'package:staffmint/features/auth/session_state.dart';

const _accounts = [
  Membership(id: 'm1', companyId: 'c1', companyName: 'Sharma Medical', role: 'owner', businessType: 'pharmacy'),
  Membership(id: 'm2', companyId: 'c2', companyName: 'Gupta Sweets', role: 'employee', businessType: 'restaurant'),
  Membership(id: 'm3', companyId: 'c3', companyName: 'Verma Traders', role: 'ca', businessType: 'shop'),
];

class _FakeAuth extends AuthController {
  static final chosen = <String>[];
  static int logouts = 0;
  static bool pendingPunches = false;
  static bool forced = true;

  @override
  SessionState build() => SessionState(
    status: SessionStatus.authenticated,
    user: const User(id: 'u1', phone: '9876543210', name: 'Rakesh', role: UserRole.owner, companyId: 'c1'),
    memberships: _accounts,
    activeMembershipId: 'm1',
    needsAccountChoice: forced,
  );

  @override
  Future<void> chooseAccount(String membershipId) async {
    if (pendingPunches) throw const PendingPunchesException(2);
    chosen.add(membershipId);
    final m = _accounts.firstWhere((a) => a.id == membershipId);
    state = state.copyWith(
      user: User(id: 'u1', phone: '9876543210', name: 'Rakesh', role: m.role, companyId: m.companyId),
      activeMembershipId: membershipId,
      needsAccountChoice: false,
    );
  }

  @override
  Future<void> logout() async => logouts++;
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'sm_language': 'en'});
    prefs = await SharedPreferences.getInstance();
    _FakeAuth.chosen.clear();
    _FakeAuth.logouts = 0;
    _FakeAuth.pendingPunches = false;
    _FakeAuth.forced = true;
  });

  Future<GoRouter> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    Widget page(String name) => Scaffold(body: Center(child: Text(name)));
    final router = GoRouter(
      initialLocation: Routes.accounts,
      routes: [
        GoRoute(path: Routes.accounts, builder: (_, _) => const AccountsScreen()),
        GoRoute(path: Routes.accountsNew, builder: (_, _) => page('new business page')),
        GoRoute(path: Routes.ownerHome, builder: (_, _) => page('owner home')),
        GoRoute(path: Routes.employeeHome, builder: (_, _) => page('staff home')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authControllerProvider.overrideWith(_FakeAuth.new),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('after login, every business is listed with its role; picking one opens its home', (tester) async {
    await pump(tester);
    expect(find.text('Choose an account'), findsOneWidget);
    expect(find.text('Sharma Medical'), findsOneWidget);
    expect(find.text('Gupta Sweets'), findsOneWidget);
    expect(find.text('Verma Traders'), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('Staff'), findsOneWidget);
    expect(find.text('Accountant'), findsOneWidget);
    expect(find.text('Open now'), findsOneWidget);
    // Forced choice: no close button, but logging out is possible.
    expect(find.byKey(const Key('accountsClose')), findsNothing);
    expect(find.text('Log out'), findsOneWidget);

    await tester.tap(find.byKey(const Key('account-m2')));
    await tester.pumpAndSettle();
    expect(_FakeAuth.chosen, ['m2']);
    expect(find.text('staff home'), findsOneWidget);
  });

  testWidgets('owners see "Add another business"; it opens the new-business flow', (tester) async {
    await pump(tester);
    expect(find.text('Add another business'), findsOneWidget);
    await tester.tap(find.byKey(const Key('newBusiness')));
    await tester.pumpAndSettle();
    expect(find.text('new business page'), findsOneWidget);
  });

  testWidgets('unsent offline check-ins stop the switch with an explanation', (tester) async {
    _FakeAuth.pendingPunches = true;
    await pump(tester);
    await tester.tap(find.byKey(const Key('account-m2')));
    // The card keeps its spinner behind the dialog, so don't wait for it to settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('2 check-ins not sent yet'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Choose an account'), findsOneWidget);
  });

  testWidgets('opened from Profile it can be closed, and has no log out', (tester) async {
    _FakeAuth.forced = false;
    await pump(tester);
    expect(find.text('Switch account'), findsOneWidget);
    expect(find.byKey(const Key('accountsClose')), findsOneWidget);
    expect(find.text('Log out'), findsNothing);
  });
}
