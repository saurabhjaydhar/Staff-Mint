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
    String? reason,
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
    SharedPreferences.setMockInitialValues({'sm_language': 'en', 'sm_tips_home_v1': true});
    prefs = await SharedPreferences.getInstance();
    api = _FakeAttendanceApi();
  });

  Future<void> pump(
    WidgetTester tester, {
    List<DayRow> Function(String date) rows = _rows,
    HomeChecklist? setup,
    MonthGrid? month,
  }) async {
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
          dayAttendanceProvider.overrideWith((ref, date) async => rows(date)),
          if (month != null) monthGridProvider.overrideWith((ref, m) async => month),
          if (month != null) employeeMonthProvider.overrideWith((ref, q) async => month),
          dashboardProvider.overrideWith(
            (ref) async => Dashboard(
              date: Dates.toApiDate(DateTime.now()),
              counts: const DashboardCounts(total: 6),
              setup: setup,
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

  testWidgets('Home: name once, Day | Month in words, "4 of 6 at work", headings and a reason on each row', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Sharma Medical'), findsOneWidget);
    expect(find.textContaining('Today, '), findsOneWidget);
    expect(find.byKey(const Key('dayTab')), findsOneWidget);
    expect(find.byKey(const Key('monthTab')), findsOneWidget);
    expect(find.text('4 of 6 at work'), findsOneWidget);
    for (final chip in ['2 present', '1 late', '1 half day', '1 on leave', '1 not in yet']) {
      expect(find.text(chip), findsOneWidget);
    }
    expect(find.text('In at'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Status ▾'), findsOneWidget);

    expect(find.text('8:56'), findsOneWidget);
    expect(inPill('e1', 'Present'), findsOneWidget);
    expect(find.text('No lock'), findsOneWidget);
    expect(inPill('e2', 'Late'), findsOneWidget);
    expect(find.text('38 min late'), findsOneWidget);
    expect(find.text('Leave approved'), findsOneWidget);
    expect(inPill('e4', 'Check'), findsOneWidget);
    expect(find.text('560 m from shop'), findsOneWidget);
    expect(find.text('Lock ✗'), findsOneWidget);
    expect(find.text('Not checked in yet'), findsOneWidget);
    expect(find.text('Changed by owner'), findsOneWidget);
    // Tappable statuses show a ▾.
    expect(
      find.descendant(of: find.byKey(const Key('pill_e5')), matching: find.byIcon(Icons.arrow_drop_down_rounded)),
      findsOneWidget,
    );

    // Approvals say what each request is, and expand into the cards.
    expect(find.text('1 thing needs your OK'), findsOneWidget);
    expect(find.text('Amit asked for leave'), findsOneWidget);
    await tester.tap(find.byKey(const Key('needsYouCard')));
    await tester.pumpAndSettle();
    expect(find.text('Amit wants leave'), findsOneWidget);
    expect(find.text('Say no'), findsOneWidget);
    expect(find.byType(Dismissible), findsOneWidget);
  });

  testWidgets('status sheet: pick what happened, reason optional, nothing saved until Save; Undo clears', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('pill_e5')));
    await tester.pumpAndSettle();
    expect(find.text('What happened this day?'), findsOneWidget);
    expect(find.text('no pay'), findsOneWidget);

    await tester.tap(find.byKey(const Key('quickStatus_absent')));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty);
    await tester.tap(find.byKey(const Key('quickSave')));
    await tester.pumpAndSettle();

    expect(api.calls.single, {
      'call': 'override',
      'employeeId': 'e5',
      'date': Dates.toApiDate(DateTime.now()),
      'status': 'absent',
      'reason': null,
    });
    expect(find.text('Amit Verma marked Absent'), findsOneWidget);

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

  testWidgets('a chosen reason is sent; Undo restores an earlier owner override', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('pill_e6')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quickStatus_present')));
    await tester.tap(find.byKey(const Key('quickReason_1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('quickSave')));
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

  testWidgets('tapping anywhere on a row opens the same sheet', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('ledgerRow_e5')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quickStatus_half_day')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('quickSave')));
    await tester.pumpAndSettle();
    expect(api.calls.single['call'], 'override');
    expect(api.calls.single['status'], 'half_day');
  });

  testWidgets('a weekly-off day says so instead of "0 of 6"; the list is one tap away', (tester) async {
    await pump(
      tester,
      rows: (date) => [for (final r in _rows(date)) DayRow(employee: r.employee, displayStatus: 'week_off')],
    );
    expect(find.text('Weekly off today'), findsOneWidget);
    expect(find.byKey(const Key('atWorkSummary')), findsNothing);
    await tester.tap(find.byKey(const Key('showOffList')));
    await tester.pumpAndSettle();
    expect(find.text('0 of 0 at work'), findsOneWidget);
  });

  testWidgets('new shop: checklist ticks itself; invite banner says who hasn\'t joined; hide works', (tester) async {
    await pump(tester, setup: const HomeChecklist(staffAdded: true, staff: 6, joined: 2, notJoined: 4));
    expect(find.text('Let’s get your shop running'), findsOneWidget);
    expect(find.text('2 of 5'), findsOneWidget);
    expect(find.text('6 staff invited · 2 have joined'), findsOneWidget);
    expect(find.byKey(const Key('remindInvites')), findsOneWidget);
    await tester.tap(find.byKey(const Key('setupHide')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('setupChecklist')), findsNothing);
    expect(prefs.getBool('sm_setup_hidden_c1'), isTrue);
  });

  testWidgets('Month: a list with totals in words; tap a person for their calendar with a legend', (tester) async {
    final today = Dates.today();
    final d1 = Dates.toApiDate(DateTime(today.year, today.month, 1));
    await pump(
      tester,
      month: MonthGrid(
        month: Dates.toApiMonth(today),
        days: [d1],
        rows: [
          MonthRow(
            employee: const EmployeeRef(id: 'e2', name: 'Pooja Singh'),
            days: {d1: 'late'},
            totals: const {
              'present': 8,
              'late': 2,
              'absent': 1,
              'halfDay': 0,
              'leave': 1,
              'weekOff': 2,
              'holiday': 0,
              'notMarked': 0,
            },
          ),
        ],
      ),
    );
    await tester.tap(find.byKey(const Key('monthTab')));
    await tester.pumpAndSettle();
    expect(find.text('Person · tap for their calendar'), findsOneWidget);
    expect(find.text('2 late · 1 absent · 1 on leave'), findsOneWidget);
    expect(find.text('8 / 10'), findsOneWidget);
    expect(find.text('See everyone day by day'), findsOneWidget);

    await tester.tap(find.byKey(const Key('monthPerson_e2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('statusLegend')), findsOneWidget);
    expect(find.text('8 of 10 days present'), findsOneWidget);
    expect(find.byKey(Key('calDay_$d1')), findsOneWidget);
  });

  testWidgets('first-time tips show once', (tester) async {
    await prefs.remove('sm_tips_home_v1');
    await pump(tester);
    expect(find.textContaining('Month: see the whole month'), findsOneWidget);
    await tester.tap(find.byKey(const Key('homeTipNext')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('homeTipNext')));
    await tester.pump();
    expect(find.text('Got it'), findsOneWidget);
    await tester.tap(find.byKey(const Key('homeTipNext')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('homeTips')), findsNothing);
    expect(prefs.getBool('sm_tips_home_v1'), isTrue);
  });
}
