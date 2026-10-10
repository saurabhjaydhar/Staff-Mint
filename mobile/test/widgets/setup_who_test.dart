import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/core/storage/providers.dart';
import 'package:staffmint/features/auth/auth_controller.dart';
import 'package:staffmint/features/auth/session_state.dart';
import 'package:staffmint/features/setup/setup_screen.dart';

class _FakeAuth extends AuthController {
  static int rechecks = 0;
  static int logouts = 0;
  static bool linkOnRecheck = false;

  @override
  SessionState build() => const SessionState(
    status: SessionStatus.authenticated,
    user: User(id: 'u9', phone: '+919876512345', name: '', role: UserRole.owner),
    needsCompanySetup: true,
  );

  @override
  Future<bool> recheckStaffLink() async {
    rechecks++;
    return linkOnRecheck;
  }

  @override
  Future<void> logout() async => logouts++;
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'sm_language': 'en'});
    prefs = await SharedPreferences.getInstance();
    _FakeAuth.rechecks = 0;
    _FakeAuth.logouts = 0;
    _FakeAuth.linkOnRecheck = false;
  });

  Future<void> pump(WidgetTester tester) async {
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

  testWidgets('a new number is asked "owner or staff" before any business setup', (tester) async {
    await pump(tester);
    expect(find.text('How will you use StaffMint?'), findsOneWidget);
    expect(find.text('Step 1 of 5'), findsNothing);

    await tester.tap(find.byKey(const Key('iAmOwner')));
    await tester.pumpAndSettle();
    expect(find.textContaining('of 5'), findsOneWidget);

    // Back from the first setup step returns to the question.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('How will you use StaffMint?'), findsOneWidget);
  });

  testWidgets('staff are told to ask their employer, and can check again or switch number', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('iAmStaff')));
    await tester.pumpAndSettle();
    expect(find.text('Ask your employer to add you'), findsOneWidget);
    expect(find.text('+91 98765 12345'), findsOneWidget);

    await tester.tap(find.byKey(const Key('checkAgain')));
    await tester.pumpAndSettle();
    expect(_FakeAuth.rechecks, 1);
    expect(find.textContaining('Not added yet'), findsOneWidget);

    await tester.tap(find.text('Use another number'));
    await tester.pumpAndSettle();
    expect(_FakeAuth.logouts, 1);
  });
}
