import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staffmint/core/api/providers.dart';
import 'package:staffmint/core/api/services/attendance_api.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/core/storage/providers.dart';
import 'package:staffmint/core/utils/dates.dart';
import 'package:staffmint/features/auth/auth_controller.dart';
import 'package:staffmint/features/auth/session_state.dart';
import 'package:staffmint/features/employee/attendance/employee_attendance_screen.dart';
import 'package:staffmint/features/employee/employee_providers.dart';
import 'package:staffmint/features/employee/leave/employee_leave_screen.dart';
import 'package:staffmint/features/employee/punch/punch_providers.dart';

class _FakeAuth extends AuthController {
  @override
  SessionState build() => const SessionState(
    status: SessionStatus.authenticated,
    user: User(
      id: 'u1',
      phone: '9876543210',
      name: 'Ramesh',
      role: UserRole.employee,
      companyId: 'c1',
      employeeId: 'e1',
    ),
    company: Company(id: 'c1', name: 'Sharma Medical', businessType: 'pharmacy'),
  );
}

class _FakeAttendanceApi implements AttendanceApi {
  final asked = <String>[];

  @override
  Future<bool> requestFix(String date, {String? note}) async {
    asked.add('$date:${note ?? ''}');
    return true;
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

  Future<void> pump(WidgetTester tester, Widget home, List overrides) async {
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

  testWidgets('My attendance: legend on top; a missed day can be sent to the owner to fix', (tester) async {
    final api = _FakeAttendanceApi();
    final month = Dates.firstOfMonth(DateTime.now());
    final d1 = Dates.toApiDate(month);
    await pump(tester, const EmployeeAttendanceScreen(), [
      attendanceApiProvider.overrideWithValue(api),
      employeeTodayProvider.overrideWith(
        (ref) async => TodayState(info: TodayInfo(date: Dates.toApiDate(DateTime.now()))),
      ),
      myMonthProvider.overrideWith(
        (ref, m) async => MonthGrid(
          month: m,
          days: [d1],
          rows: [
            MonthRow(
              employee: const EmployeeRef(id: 'e1', name: 'Ramesh'),
              days: {d1: 'absent'},
              totals: const {'present': 0, 'absent': 1},
            ),
          ],
        ),
      ),
    ]);
    expect(find.byKey(const Key('statusLegend')), findsOneWidget);
    expect(find.text('0 of 1 days present'), findsOneWidget);
    if (Dates.isSameDay(month, Dates.today())) return; // the 1st is today: nothing to fix yet
    await tester.tap(find.byKey(Key('calDay_$d1')));
    await tester.pumpAndSettle();
    expect(find.text('No check-in that day.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askFix')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('askFixNote')), 'I was at the bank');
    await tester.tap(find.byKey(const Key('askFixSend')));
    await tester.pumpAndSettle();
    expect(api.asked, ['$d1:I was at the bank']);
    expect(find.text('Sent to your owner'), findsOneWidget);
  });

  testWidgets('Ask for leave shows leaves left and the effect before sending', (tester) async {
    await pump(tester, const EmployeeLeaveScreen(), [
      myLeavesProvider.overrideWith((ref) async => const <Leave>[]),
      myLeaveBalancesProvider.overrideWith(
        (ref) async => const [LeaveBalance(employeeId: 'e1', year: 2026, paid: 4, sick: 2)],
      ),
    ]);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('You have 4 paid leaves left'), findsOneWidget);
    // Default: one day of paid leave tomorrow.
    expect(find.text('After this you’ll have 3 paid leaves left. Your salary won’t be cut.'), findsOneWidget);
    await tester.tap(find.text('Unpaid leave'));
    await tester.pumpAndSettle();
    expect(find.text('Unpaid leave: salary is cut for these days.'), findsOneWidget);
    expect(find.text('Send to owner'), findsOneWidget);
  });
}
