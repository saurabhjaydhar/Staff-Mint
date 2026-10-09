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
import 'package:staffmint/features/owner/providers/owner_providers.dart';
import 'package:staffmint/features/owner/today/today_screen.dart';

class _FakeAuth extends AuthController {
  @override
  SessionState build() => const SessionState(
    status: SessionStatus.authenticated,
    user: User(id: 'u1', phone: '9876543210', name: 'Owner', role: UserRole.owner, companyId: 'c1'),
    company: Company(id: 'c1', name: 'Sharma Medical', businessType: 'pharmacy'),
  );
}

/// Records override / clear-override calls; everything else is unused here.
class _FakeAttendanceApi implements AttendanceApi {
  final List<Map<String, Object?>> calls = [];

  @override
  Future<Attendance> overrideStatus({
    required String employeeId,
    required String date,
    required String status,
    String? leaveType,
    required String reason,
  }) async {
    calls.add({'call': 'override', 'employeeId': employeeId, 'date': date, 'status': status, 'reason': reason});
    return Attendance(id: 'a-$employeeId', employeeId: employeeId, date: date, status: status, overridden: true);
  }

  @override
  Future<Attendance> clearOverride({required String employeeId, required String date, required String reason}) async {
    calls.add({'call': 'clear', 'employeeId': employeeId, 'date': date, 'reason': reason});
    return Attendance(id: 'a-$employeeId', employeeId: employeeId, date: date);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DateTime _at(int h, int m) {
  final t = Dates.today();
  return DateTime(t.year, t.month, t.day, h, m);
}

List<DayRow> _rows(String date) => [
  DayRow(
    employee: const EmployeeRef(id: 'e1', name: 'Ramesh Kumar'),
    record: Attendance(
      id: 'a1',
      employeeId: 'e1',
      date: date,
      status: 'present',
      punches: [Punch(id: 'p1', type: 'in', clientTime: _at(8, 56), lockCheck: 'unavailable')],
    ),
    displayStatus: 'present',
  ),
  DayRow(
    employee: const EmployeeRef(id: 'e2', name: 'Suresh Yadav'),
    record: Attendance(
      id: 'a2',
      employeeId: 'e2',
      date: date,
      status: 'present',
      lateMinutes: 38,
      punches: [Punch(id: 'p2', type: 'in', clientTime: _at(9, 38))],
    ),
    displayStatus: 'late',
  ),
  const DayRow(
    employee: EmployeeRef(id: 'e3', name: 'Ramesh Gupta'),
    displayStatus: 'leave',
  ),
  DayRow(
    employee: const EmployeeRef(id: 'e4', name: 'Raju'),
    record: Attendance(
      id: 'a4',
      employeeId: 'e4',
      date: date,
      punches: [
        Punch(
          id: 'p4',
          type: 'in',
          clientTime: _at(9, 10),
          distanceM: 560,
          insideGeofence: false,
          approval: 'pending',
          lockCheck: 'failed',
        ),
      ],
    ),
    displayStatus: 'checked_in',
  ),
  const DayRow(
    employee: EmployeeRef(id: 'e5', name: 'Amit Verma'),
    displayStatus: 'not_marked',
  ),
  DayRow(
    employee: const EmployeeRef(id: 'e6', name: 'Pooja Singh'),
    record: Attendance(id: 'a6', employeeId: 'e6', date: date, status: 'half_day', overridden: true),
    displayStatus: 'half_day',
  ),
];

void main() {
  late SharedPreferences prefs;
  late _FakeAttendanceApi api;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'sm_language': 'en'});
    prefs = await SharedPreferences.getInstance();
    api = _FakeAttendanceApi();
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
          attendanceApiProvider.overrideWithValue(api),
          dayAttendanceProvider.overrideWith((ref, date) async => _rows(date)),
          dashboardProvider.overrideWith(
            (ref) async => Dashboard(
              date: Dates.toApiDate(DateTime.now()),
              counts: const DashboardCounts(total: 6),
              leaveRequests: const [
                Leave(
                  id: 'l1',
                  employeeId: 'e5',
                  employeeName: 'Amit',
                  type: 'sick',
                  from: '2026-10-10',
                  to: '2026-10-10',
                  days: 1,
                ),
              ],
            ),
          ),
        ],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder inPill(String id, String text) => find.descendant(of: find.byKey(Key('pill_$id')), matching: find.text(text));

  testWidgets('Today ledger shows the day sheet with times, meta and status pills', (tester) async {
    await pump(tester);

    expect(find.text('Today’s attendance'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('ledgerBigNumber'))).textSpan!.toPlainText(), '4 / 6');
    expect(find.text('Late 1'), findsOneWidget);
    expect(find.text('Leave 1'), findsOneWidget);
    expect(find.text('Not yet 1'), findsOneWidget);

    expect(find.text('Ramesh Kumar'), findsOneWidget);
    expect(find.text('8:56'), findsOneWidget);
    expect(inPill('e1', 'Present'), findsOneWidget);
    expect(inPill('e2', 'Late'), findsOneWidget);
    expect(find.text('38 min'), findsOneWidget);
    expect(inPill('e3', 'Leave'), findsOneWidget);
    expect(inPill('e4', 'Check'), findsOneWidget);
    // Distance and phone-lock tags share the row's meta line.
    expect(find.text('560 m · Lock ✗'), findsOneWidget);
    expect(find.text('No lock'), findsOneWidget);
    expect(inPill('e5', 'Not yet'), findsOneWidget);

    // The "needs you" card summarises pending work and expands into swipe cards.
    expect(find.text('1 thing needs you'), findsOneWidget);
    await tester.tap(find.byKey(const Key('needsYouCard')));
    await tester.pumpAndSettle();
    expect(find.text('Swipe right to approve, left to reject'), findsOneWidget);
    expect(find.byType(Dismissible), findsOneWidget);
  });

  testWidgets('status pill → quick sheet saves at once; Undo clears an implicit day', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('pill_e5')));
    await tester.pumpAndSettle();

    // First reason chip is pre-selected; one tap on a status saves.
    await tester.tap(find.byKey(const Key('quickStatus_absent')));
    await tester.pumpAndSettle();

    expect(api.calls, hasLength(1));
    expect(api.calls.single, {
      'call': 'override',
      'employeeId': 'e5',
      'date': Dates.toApiDate(DateTime.now()),
      'status': 'absent',
      'reason': 'Owner confirmed',
    });
    expect(find.text('Amit Verma: Absent · saved'), findsOneWidget);

    await tester.tap(find.byKey(const Key('undoAction')));
    await tester.pumpAndSettle();
    expect(api.calls.last, {
      'call': 'clear',
      'employeeId': 'e5',
      'date': Dates.toApiDate(DateTime.now()),
      'reason': 'Undo',
    });
    expect(find.text('Change undone'), findsOneWidget);
  });

  testWidgets('a chosen reason chip is sent; Undo restores an earlier owner override', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('pill_e6')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quickReason_1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('quickStatus_present')));
    await tester.pump();

    // Optimistic: the row flips before the server answers.
    expect(inPill('e6', 'Present'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(api.calls.single['reason'], 'Doctor');

    await tester.tap(find.byKey(const Key('undoAction')));
    await tester.pumpAndSettle();
    expect(api.calls.last, {
      'call': 'override',
      'employeeId': 'e6',
      'date': Dates.toApiDate(DateTime.now()),
      'status': 'half_day',
      'reason': 'Undo',
    });
  });

  testWidgets('tapping anywhere on a row opens the same 2-tap quick sheet', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('ledgerRow_e5')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quickStatus_half_day')));
    await tester.pumpAndSettle();
    expect(api.calls.single['call'], 'override');
    expect(api.calls.single['status'], 'half_day');
  });
}
