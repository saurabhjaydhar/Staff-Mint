import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/core/storage/providers.dart';
import 'package:staffmint/features/auth/auth_controller.dart';
import 'package:staffmint/features/auth/session_state.dart';
import 'package:staffmint/features/owner/today/trial_banner.dart';

const _owner = User(id: 'u1', phone: '+919876512345', name: 'Ravi', role: UserRole.owner);
const _staff = User(id: 'u2', phone: '+919876512346', name: 'Suresh', role: UserRole.employee);

class _FakeAuth extends AuthController {
  static SessionState initial = const SessionState(status: SessionStatus.unauthenticated);
  @override
  SessionState build() => initial;
}

Company _company(Trial? trial) => Company(id: 'c1', name: 'Gupta Sweets', businessType: 'shop', trial: trial);

Trial _trial(Duration fromNow) => Trial(
  planCode: 'pro',
  planName: 'Pro',
  endsAt: DateTime.now().add(fromNow),
  paidFeatures: const ['payroll', 'payslips', 'face_match', 'priority_support'],
);

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'sm_language': 'en'});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> pump(WidgetTester tester, {required User user, Trial? trial}) async {
    _FakeAuth.initial = SessionState(status: SessionStatus.authenticated, user: user, company: _company(trial));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authControllerProvider.overrideWith(_FakeAuth.new),
        ],
        child: const MaterialApp(home: Scaffold(body: TrialBanner())),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('days left counts part of a day as one', () {
    final now = DateTime(2026, 10, 11, 12);
    final t = Trial(planCode: 'pro', planName: 'Pro', endsAt: DateTime(2026, 10, 25, 12));
    expect(t.daysLeftAt(now), 14);
    expect(t.daysLeftAt(DateTime(2026, 10, 24, 18)), 1);
    expect(t.daysLeftAt(DateTime(2026, 10, 25, 13)), 0);
    expect(t.activeAt(DateTime(2026, 10, 25, 13)), isFalse);
  });

  testWidgets('owners see the countdown with a way to the plans', (tester) async {
    await pump(tester, user: _owner, trial: _trial(const Duration(days: 9, hours: 2)));
    expect(find.text('Pro free trial: 10 days left'), findsOneWidget);
    expect(find.textContaining('All features are on until'), findsOneWidget);
    expect(find.text('See plans'), findsOneWidget);
  });

  testWidgets('the last days warn what happens next', (tester) async {
    await pump(tester, user: _owner, trial: _trial(const Duration(hours: 20)));
    expect(find.text('Pro free trial: last day'), findsOneWidget);
    expect(find.textContaining('you move to Free: your data stays'), findsOneWidget);
  });

  testWidgets('after the trial: what keeps working, what is paused, and it can be dismissed', (tester) async {
    await pump(tester, user: _owner, trial: _trial(const Duration(days: -2)));
    expect(find.text('Your free trial has ended'), findsOneWidget);
    expect(find.textContaining('Attendance, leave and the daily summary keep working'), findsOneWidget);
    expect(find.textContaining('Paused until you pick a plan: Salary, Payslips, Face check.'), findsOneWidget);
    expect(find.text('Upgrade'), findsOneWidget);
    await tester.tap(find.byTooltip('OK'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trialEndedBanner')), findsNothing);
    // Stays dismissed next time.
    await pump(tester, user: _owner, trial: _trial(const Duration(days: -2)));
    expect(find.byKey(const Key('trialEndedBanner')), findsNothing);
  });

  testWidgets('staff and businesses without a trial see nothing', (tester) async {
    await pump(tester, user: _staff, trial: _trial(const Duration(days: 9)));
    expect(find.byKey(const Key('trialBanner')), findsNothing);
    await pump(tester, user: _owner);
    expect(find.byKey(const Key('trialBanner')), findsNothing);
  });
}
