import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/core/storage/providers.dart';
import 'package:staffmint/features/auth/auth_controller.dart';
import 'package:staffmint/features/auth/session_state.dart';
import 'package:staffmint/features/setup/setup_screen.dart';

const _user = User(id: 'u1', phone: '+919876512345', name: 'Ravi', role: UserRole.owner);

class _FakeAuth extends AuthController {
  static SessionState initial = const SessionState(status: SessionStatus.unauthenticated);
  static final requested = <String>[];
  static final dismissed = <String>[];
  static final restored = <String>[];

  @override
  SessionState build() => initial;

  @override
  Future<String> requestDeviceChange(String membershipId) async {
    requested.add(membershipId);
    return 'pending';
  }

  @override
  Future<void> dismissNotice(String membershipId) async {
    dismissed.add(membershipId);
    state = state.copyWith(endedNotices: [...state.endedNotices.where((n) => n.id != membershipId)]);
  }

  @override
  Future<void> restoreBusiness(String companyId) async => restored.add(companyId);
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'sm_language': 'en'});
    prefs = await SharedPreferences.getInstance();
    _FakeAuth.requested.clear();
    _FakeAuth.dismissed.clear();
    _FakeAuth.restored.clear();
  });

  Future<void> pump(WidgetTester tester, SessionState session) async {
    _FakeAuth.initial = session;
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authControllerProvider.overrideWith(_FakeAuth.new),
        ],
        child: const MaterialApp(home: SetupScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('removed staff see why they have no business, and can dismiss it', (tester) async {
    await pump(
      tester,
      SessionState(
        status: SessionStatus.authenticated,
        user: _user,
        needsCompanySetup: true,
        endedNotices: [
          EndedNotice(id: 'm1', companyName: 'Gupta Sweets', endedAt: DateTime(2026, 10, 3, 12), reason: 'removed'),
        ],
      ),
    );
    expect(find.text('Your access to Gupta Sweets ended on 3 Oct'), findsOneWidget);
    expect(find.text('Your employer removed you from their staff.'), findsOneWidget);
    // The usual "owner or staff?" choice is still right there.
    expect(find.byKey(const Key('iAmOwner')), findsOneWidget);
    await tester.tap(find.byTooltip('OK, got it'));
    await tester.pumpAndSettle();
    expect(_FakeAuth.dismissed, ['m1']);
    expect(find.textContaining('Gupta Sweets'), findsNothing);
  });

  testWidgets('a closed business can be restored from the start screen', (tester) async {
    await pump(
      tester,
      SessionState(
        status: SessionStatus.authenticated,
        user: _user,
        needsCompanySetup: true,
        closedBusinesses: [
          ClosedBusiness(companyId: 'c1', companyName: 'Sharma Medical', restoreUntil: DateTime(2026, 11, 9)),
        ],
      ),
    );
    expect(find.text('Sharma Medical'), findsOneWidget);
    expect(find.text('Restore until 9 Nov'), findsOneWidget);
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(_FakeAuth.restored, ['c1']);
  });

  testWidgets('a staff account on another phone offers "Request this phone", not a dead end', (tester) async {
    const locked = Membership(
      id: 'm7',
      companyId: 'c7',
      companyName: 'Gupta Sweets',
      role: 'employee',
      lockedToOtherPhone: true,
    );
    await pump(
      tester,
      const SessionState(
        status: SessionStatus.authenticated,
        user: _user,
        needsCompanySetup: true,
        memberships: [locked],
        blockedAccounts: [locked],
      ),
    );
    expect(find.text('Your staff account at Gupta Sweets is on another phone'), findsOneWidget);
    await tester.tap(find.byKey(const Key('requestPhone-m7')));
    await tester.pumpAndSettle();
    expect(_FakeAuth.requested, ['m7']);
    expect(find.text('Request sent. We will tell you when it is approved.'), findsWidgets);
    // They can still start their own business instead.
    await tester.tap(find.text('I want my own business'));
    await tester.pumpAndSettle();
    expect(find.textContaining('of 5'), findsOneWidget);
  });
}
