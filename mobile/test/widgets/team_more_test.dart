import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staffmint/core/api/providers.dart';
import 'package:staffmint/core/api/services/company_api.dart';
import 'package:staffmint/core/api/services/employees_api.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/core/storage/providers.dart';
import 'package:staffmint/core/utils/json.dart';
import 'package:staffmint/features/auth/auth_controller.dart';
import 'package:staffmint/features/auth/session_state.dart';
import 'package:staffmint/features/owner/more/accountants_screen.dart';
import 'package:staffmint/features/owner/more/more_screen.dart';
import 'package:staffmint/features/owner/more/owners_screen.dart';
import 'package:staffmint/features/owner/more/rules_screens.dart';
import 'package:staffmint/features/owner/providers/owner_providers.dart';
import 'package:staffmint/features/owner/salary/money_dialogs.dart';
import 'package:staffmint/features/owner/staff/team_screen.dart';

class _FakeAuth extends AuthController {
  @override
  SessionState build() => const SessionState(
    status: SessionStatus.authenticated,
    user: User(id: 'u1', phone: '9876543210', name: 'Rakesh', role: UserRole.owner, companyId: 'c1'),
    company: Company(id: 'c1', name: 'Sharma Medical', businessType: 'pharmacy'),
  );

  @override
  Future<void> refreshMe({bool? needsCompanySetupHint, bool? needsAccountChoice}) async {}
}

class _FakeEmployeesApi implements EmployeesApi {
  final calls = <String>[];

  @override
  Future<Employee> setRole(String id, String role, {bool allBranches = false}) async {
    calls.add('$id:$role:$allBranches');
    return Employee(id: id, name: 'x', phone: '', appRole: role);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCompanyApi implements CompanyApi {
  Json? saved;

  @override
  Future<Company> updateSettings(Json partial) async {
    saved = partial;
    return const Company(id: 'c1', name: 'Sharma Medical', businessType: 'pharmacy');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _staff = [
  Employee(id: 'e1', name: 'Ramesh Kumar', phone: '1', designation: 'Sales', appRole: 'manager', linked: true),
  Employee(id: 'e2', name: 'Pooja Singh', phone: '2', designation: 'Cashier', ratePaise: 1200000, linked: true),
];

void main() {
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'sm_language': 'en'});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> pump(WidgetTester tester, Widget home, {List overrides = const []}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authControllerProvider.overrideWith(_FakeAuth.new),
          ...overrides.cast(),
        ],
        child: MaterialApp(home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Team & access: each role says what it can do; Make manager shows can / can’t first', (tester) async {
    final api = _FakeEmployeesApi();
    await pump(
      tester,
      const TeamScreen(),
      overrides: [
        employeesApiProvider.overrideWithValue(api),
        employeesProvider.overrideWith((ref, q) async => _staff),
        ownersProvider.overrideWith(
          (ref) async => const [
            OwnerItem(id: 'o1', name: 'Rakesh', phone: '1', isMain: true, isYou: true),
            OwnerItem(id: 'o2', name: 'Meena Sharma', phone: '2'),
          ],
        ),
        accountantsProvider.overrideWith((ref) async => const <Accountant>[]),
        branchesProvider.overrideWith((ref) async => const <Branch>[]),
      ],
    );
    expect(find.text('Partners (co-owners)'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Meena Sharma'), findsOneWidget);
    expect(find.text('Mark attendance and approve leave. Can’t see salary or billing.'), findsOneWidget);
    expect(find.text('Ramesh Kumar'), findsOneWidget);
    expect(find.text('Add your CA'), findsOneWidget);

    await tester.tap(find.byKey(const Key('makeManagerAction')));
    await tester.pumpAndSettle();
    // Ramesh is already a manager, so only Pooja is offered.
    expect(find.byKey(const Key('pickManager_e1')), findsNothing);
    await tester.tap(find.byKey(const Key('pickManager_e2')));
    await tester.pumpAndSettle();
    expect(find.text('Make Pooja Singh a manager?'), findsOneWidget);
    expect(find.text('Salary, advances or salary slips of others'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmMakeManager')));
    await tester.pumpAndSettle();
    expect(api.calls, ['e2:manager:false']);
    expect(find.text('Pooja Singh is now a manager'), findsOneWidget);
  });

  testWidgets('More: small groups, and search finds a setting by everyday words', (tester) async {
    await pump(
      tester,
      const MoreScreen(),
      overrides: [
        dashboardProvider.overrideWith((ref) async => const Dashboard(date: '2026-10-12', counts: DashboardCounts())),
      ],
    );
    expect(find.text('Shop rules'), findsOneWidget);
    expect(find.text('Attendance rules'), findsOneWidget);
    expect(find.text('History of changes'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('moreSearch')), 'CA');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('more_team')), findsOneWidget);
    expect(find.byKey(const Key('more_attendanceRules')), findsNothing);

    await tester.enterText(find.byKey(const Key('moreSearch')), 'लेट');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('more_attendanceRules')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('moreSearch')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('moreNothing')), findsOneWidget);
  });

  testWidgets('Attendance rules show a real example and save only what changed', (tester) async {
    final api = _FakeCompanyApi();
    await pump(
      tester,
      const AttendanceRulesScreen(),
      overrides: [
        companyApiProvider.overrideWithValue(api),
        companyProvider.overrideWith(
          (ref) async => const Company(id: 'c1', name: 'Sharma Medical', businessType: 'pharmacy'),
        ),
      ],
    );
    expect(find.text('Late after 15 min'), findsOneWidget);
    expect(find.text('Shift starts 9:00 → 9:16 counts as Late.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('grace_10')));
    await tester.pumpAndSettle();
    expect(find.text('Shift starts 9:00 → 9:11 counts as Late.'), findsOneWidget);
    expect(find.text('Changes apply from today. Past days stay as they are.'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('saveRules')), 300);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saveRules')));
    await tester.pumpAndSettle();
    expect(api.saved, {'graceMinutes': 10});
  });

  testWidgets('Give an advance shows the effect on the next salary before saving', (tester) async {
    await pump(
      tester,
      Consumer(
        builder: (context, ref, _) => Scaffold(
          body: TextButton(
            onPressed: () => showAddAdvanceSheet(context, ref, employee: _staff[1]),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Give an advance (udhaar)'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '2000');
    await tester.pumpAndSettle();
    expect(find.textContaining('Pooja’s'), findsOneWidget);
    expect(find.textContaining('about ₹10,000 instead of ₹12,000'), findsOneWidget);
    expect(find.text('Give ₹2,000'), findsOneWidget);
  });
}
