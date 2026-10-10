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

const _names = [
  'Alpha Medical',
  'Beta Salon',
  'Gamma Foods',
  'Delta Traders',
  'Epsilon Store',
  'Zeta Clinic',
  'Eta Bakery',
];

class _FakeAuth extends AuthController {
  static final pins = <(String, bool)>[];

  @override
  SessionState build() => SessionState(
    status: SessionStatus.authenticated,
    user: const User(id: 'u1', phone: '9876543210', name: 'CA Gupta', role: UserRole.ca, companyId: 'c0'),
    memberships: [
      for (var i = 0; i < _names.length; i++)
        Membership(id: 'm$i', companyId: 'c$i', companyName: _names[i], role: 'ca', pinned: i == 5),
    ],
    activeMembershipId: 'm0',
  );

  @override
  Future<void> pinAccount(String membershipId, {required bool pinned}) async => pins.add((membershipId, pinned));
}

void main() {
  testWidgets('accountants with many clients can search and pin', (tester) async {
    SharedPreferences.setMockInitialValues({'sm_language': 'en'});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: Routes.accounts,
      routes: [GoRoute(path: Routes.accounts, builder: (_, _) => const AccountsScreen())],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authControllerProvider.overrideWith(_FakeAuth.new),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    // The pinned client comes first.
    final first = tester.getTopLeft(find.text('Zeta Clinic')).dy;
    final second = tester.getTopLeft(find.text('Alpha Medical')).dy;
    expect(first, lessThan(second));
    // Search narrows the list.
    await tester.enterText(find.byKey(const Key('accountSearch')), 'bak');
    await tester.pumpAndSettle();
    expect(find.text('Eta Bakery'), findsOneWidget);
    expect(find.text('Alpha Medical'), findsNothing);
    await tester.tap(find.byKey(const Key('pin-m6')));
    await tester.pumpAndSettle();
    expect(_FakeAuth.pins, [('m6', true)]);
  });
}
