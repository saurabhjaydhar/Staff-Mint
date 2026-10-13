import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staffmint/core/api/providers.dart';
import 'package:staffmint/core/api/services/company_api.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/core/utils/json.dart';
import 'package:staffmint/core/storage/providers.dart';
import 'package:staffmint/features/auth/auth_controller.dart';
import 'package:staffmint/features/auth/session_state.dart';
import 'package:staffmint/features/owner/more/rules_screens.dart';
import 'package:staffmint/features/owner/more/settings_screen.dart';
import 'package:staffmint/features/owner/providers/owner_providers.dart';
import 'package:staffmint/features/owner/staff/add_staff_screen.dart';
import 'package:staffmint/features/owner/staff/staff_list_screen.dart';

class _FakeAuth extends AuthController {
  @override
  SessionState build() => const SessionState(
    status: SessionStatus.authenticated,
    user: User(id: 'u1', phone: '9876543210', name: 'Owner', role: UserRole.owner, companyId: 'c1'),
    company: Company(id: 'c1', name: 'Sharma Medical', businessType: 'pharmacy'),
  );
}

const _shifts = [
  Shift(id: 's1', name: 'General', start: '09:00', end: '21:00', weeklyOff: [0], isDefault: true),
  Shift(id: 's2', name: 'Morning', start: '07:00', end: '15:00', weeklyOff: [1]),
];

const _staff = [
  Employee(id: 'e1', name: 'Pooja Singh', phone: '9876500003', ratePaise: 1400000, designation: 'Cashier'),
  Employee(id: 'e2', name: 'Raju', phone: '9876500004', shiftId: 's2'),
  Employee(id: 'e3', name: 'Old Hand', phone: '9876500009', status: 'inactive'),
];

class _FakeCompanyApi implements CompanyApi {
  final saved = <Json>[];

  @override
  Future<Company> updateSettings(Json partial) async {
    saved.add(partial);
    return const Company(id: 'c1', name: 'Sharma Medical', businessType: 'pharmacy');
  }

  @override
  Future<Shift> createShift(Json body) async {
    saved.add(body);
    return Shift(id: 's3', name: body['name'] as String, start: body['start'] as String, end: body['end'] as String);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'sm_language': 'en'});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> pump(WidgetTester tester, Widget home, {CompanyApi? companyApi}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authControllerProvider.overrideWith(_FakeAuth.new),
          shiftsProvider.overrideWith((ref) async => _shifts),
          if (companyApi != null) companyApiProvider.overrideWithValue(companyApi),
          employeesProvider.overrideWith((ref, q) async => _staff),
          activeEmployeesProvider.overrideWith((ref) async => _staff.where((e) => e.isActive).toList()),
          dayAttendanceProvider.overrideWith((ref, d) async => const <DayRow>[]),
          holidaysProvider.overrideWith(
            (ref, year) async => [
              Holiday(id: 'h$year', date: '$year-12-25', name: 'Christmas $year'),
              Holiday(id: 'p$year', date: '$year-01-01', name: 'New Year $year'),
            ],
          ),
        ],
        child: MaterialApp(home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Add staff: 3 clear ways and what happens next; the form shows real shift times', (tester) async {
    await pump(tester, const AddStaffScreen());
    expect(find.byKey(const Key('wayContacts')), findsOneWidget);
    expect(find.byKey(const Key('wayType')), findsOneWidget);
    expect(find.byKey(const Key('wayExcel')), findsOneWidget);
    expect(find.text('What happens next'), findsOneWidget);
    expect(find.text('Each person gets a WhatsApp invite with the app link.'), findsOneWidget);

    await tester.tap(find.text('Type'));
    await tester.pumpAndSettle();
    expect(find.text('New staff'), findsOneWidget);
    expect(find.text('Default shift'), findsNothing);
    expect(find.text('General · 9:00 AM – 9:00 PM · Sunday off'), findsOneWidget);
    expect(find.text('Joining date: today'), findsOneWidget);
    expect(find.text('Add & send invite'), findsOneWidget);
  });

  testWidgets('Add staff: "Add shift" in the shift list makes a new shift and picks it', (tester) async {
    final api = _FakeCompanyApi();
    await pump(tester, const AddStaffScreen(), companyApi: api);
    await tester.tap(find.text('Type'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shiftPicker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add shift').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Shift name'), 'Night');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(api.saved.single, containsPair('name', 'Night'));
    // The new shift is now the one picked.
    expect(find.text('Night · 9:00 AM – 7:00 PM · Sunday off'), findsOneWidget);
  });

  testWidgets('Staff tab: a labelled "+ Add" and Working / Left chips instead of "Show inactive"', (tester) async {
    await pump(tester, const StaffListScreen());
    expect(find.descendant(of: find.byKey(const Key('addStaff')), matching: find.text('Add')), findsOneWidget);
    expect(find.text('Show inactive'), findsNothing);
    expect(find.text('Working (2)'), findsOneWidget);
    expect(find.text('Left (1)'), findsOneWidget);
    expect(find.text('Pooja Singh'), findsOneWidget);
    expect(find.text('Old Hand'), findsNothing);
    await tester.tap(find.byKey(const Key('filterLeft')));
    await tester.pumpAndSettle();
    expect(find.text('Old Hand'), findsOneWidget);
    expect(find.text('Pooja Singh'), findsNothing);
  });

  testWidgets('Timings: shifts with staff counts and the next holidays on the page itself', (tester) async {
    await pump(tester, const TimingsScreen());
    expect(find.text('9:00 AM – 9:00 PM · Sunday off · 1 staff'), findsOneWidget);
    expect(find.text('7:00 AM – 3:00 PM · Monday off · 1 staff'), findsOneWidget);
    expect(find.text('Add shift'), findsOneWidget);
    expect(find.text('Next holidays'), findsOneWidget);
    final year = DateTime.now().year;
    expect(find.text('Christmas $year'), findsOneWidget);
    expect(find.text('New Year ${year + 1}'), findsOneWidget);
    expect(find.text('New Year $year'), findsNothing);
  });

  testWidgets('Business details: each switch says what it does and saves at once (no Save button)', (tester) async {
    final api = _FakeCompanyApi();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authControllerProvider.overrideWith(_FakeAuth.new),
          companyApiProvider.overrideWithValue(api),
          companyProvider.overrideWith(
            (ref) async => const Company(id: 'c1', name: 'Sharma Medical', businessType: 'pharmacy'),
          ),
          rulesProvider.overrideWith((ref) async => const <RuleText>[]),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Business & rules'), findsNothing);
    expect(find.text('Save'), findsNothing);
    expect(find.text('Saves as soon as you change it.'), findsOneWidget);
    expect(find.text('Alerts on WhatsApp too'), findsOneWidget);
    expect(find.text('For 12 months after they leave (for loans, ITR).'), findsOneWidget);
    expect(find.text('Team & access'), findsNothing);
    await tester.tap(find.byKey(const Key('whatsappAlerts')));
    await tester.pumpAndSettle();
    expect(api.saved, [
      {'whatsappAlerts': true},
    ]);
    expect(find.text('Saved'), findsOneWidget);
  });
}
