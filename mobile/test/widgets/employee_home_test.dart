import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staffmint/core/api/api_exception.dart';
import 'package:staffmint/core/api/services/attendance_api.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/core/storage/providers.dart';
import 'package:staffmint/core/utils/dates.dart';
import 'package:staffmint/core/utils/json.dart';
import 'package:staffmint/features/auth/auth_controller.dart';
import 'package:staffmint/features/auth/session_state.dart';
import 'package:staffmint/features/employee/employee_providers.dart';
import 'package:staffmint/features/employee/home/check_in_button.dart';
import 'package:staffmint/features/employee/home/employee_home_screen.dart';
import 'package:staffmint/features/employee/punch/punch_capture.dart';
import 'package:staffmint/features/employee/punch/punch_providers.dart';
import 'package:staffmint/features/employee/punch/punch_queue.dart';
import 'package:staffmint/features/employee/punch/punch_service.dart';
import 'package:staffmint/features/employee/punch/punch_state.dart';

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
    employee: Employee(id: 'e1', name: 'Ramesh', phone: '9876543210', locationConsent: true),
  );
}

class _FakeCapture implements PunchCapture {
  int selfies = 0;
  @override
  Future<CapturedLocation> location() async => const CapturedLocation(lat: 28.6, lng: 77.2, accuracyM: 12);
  @override
  Future<String?> selfie() async {
    selfies++;
    return 'c2VsZmll';
  }
}

/// Fake check-in API whose behaviour each test picks.
class _FakePunchApi implements PunchApi {
  _FakePunchApi(this.onPunch);
  final void Function(Json body, String type) onPunch;
  final List<Json> bodies = [];
  ApiException? error;

  @override
  Future<PunchResponse> checkIn(Json body) => _go(body, 'in');
  @override
  Future<PunchResponse> checkOut(Json body) => _go(body, 'out');

  Future<PunchResponse> _go(Json body, String type) async {
    bodies.add(body);
    if (error != null) throw error!;
    onPunch(body, type);
    return PunchResponse(
      record: Attendance(id: 'a1', employeeId: 'e1', date: Dates.toApiDate(DateTime.now())),
      punch: Punch(id: 'p1', type: type, clientTime: DateTime.now()),
    );
  }
}

void main() {
  late SharedPreferences prefs;
  late PunchQueue queue;
  late _FakeCapture capture;
  late Attendance? serverRecord;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    queue = PunchQueue(MemoryPunchQueueStore());
    capture = _FakeCapture();
    serverRecord = null;
  });

  Future<_FakePunchApi> pumpHome(WidgetTester tester) async {
    final today = Dates.toApiDate(DateTime.now());
    final api = _FakePunchApi((body, type) {
      serverRecord = Attendance(
        id: 'a1',
        employeeId: 'e1',
        date: today,
        status: 'present',
        punches: [Punch(id: 'p1', type: type, clientTime: DateTime.parse(body['clientTime'] as String))],
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authControllerProvider.overrideWith(_FakeAuth.new),
          employeeTodayProvider.overrideWith(
            (ref) async => TodayState(
              info: TodayInfo(
                date: today,
                record: serverRecord,
                shift: const Shift(id: 's1', name: 'Day', start: '09:00', end: '19:00'),
                // ~11 m north of the fake GPS fix.
                branch: const Branch(id: 'b1', name: 'Sharma Medical', location: GeoPoint(lat: 28.6001, lng: 77.2)),
              ),
            ),
          ),
          myMonthProvider.overrideWith(
            (ref, month) async => MonthGrid(
              month: month,
              days: const [],
              rows: [
                MonthRow(
                  employee: const EmployeeRef(id: 'e1', name: 'Ramesh'),
                  days: {Dates.toApiDate(DateTime.now()): 'not_marked'},
                  totals: const {},
                ),
              ],
            ),
          ),
          mySalaryProvider.overrideWith(
            (ref) async => const SalaryOverview(
              estimate: Payslip(id: '', employeeId: 'e1', employeeName: 'Ramesh', month: '2026-10', netPaise: 361300),
            ),
          ),
          punchQueueProvider.overrideWithValue(queue),
          punchServiceProvider.overrideWithValue(PunchService(api: api, queue: queue)),
          punchCaptureProvider.overrideWithValue(capture),
          connectivityOnlineProvider.overrideWithValue(const Stream<bool>.empty()),
        ],
        child: const MaterialApp(home: EmployeeHomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return api;
  }

  testWidgets('shows a big Check in button with today\'s shift', (tester) async {
    await pumpHome(tester);
    expect(find.byKey(const Key('checkInButton')), findsOneWidget);
    expect(find.text('Check in'), findsOneWidget);
    expect(find.text('You have not checked in yet'), findsOneWidget);
    expect(find.textContaining('Shift 9:00 AM – 7:00 PM'), findsOneWidget);
    expect(find.byKey(const Key('pendingSyncBanner')), findsNothing);
  });

  testWidgets('GPS is ready before the tap: "At shop" chip and month strip', (tester) async {
    await pumpHome(tester);
    final chip = find.byKey(const Key('locationChip'));
    expect(chip, findsOneWidget);
    expect(find.descendant(of: chip, matching: find.text('At shop')), findsOneWidget);
    expect(find.descendant(of: chip, matching: find.textContaining('11 m')), findsOneWidget);
    expect(find.text('₹3,613 so far'), findsOneWidget);
  });

  testWidgets('online check-in sends selfie + GPS and flips to Check out', (tester) async {
    final api = await pumpHome(tester);
    await tester.tap(find.byKey(const Key('checkInButton')));
    await tester.pumpAndSettle();

    expect(capture.selfies, 1);
    final body = api.bodies.single;
    expect(body['selfieBase64'], 'c2VsZmll');
    expect((body['geo'] as Map)['accuracyM'], 12);
    expect(body['mockLocation'], false);
    expect(body['deviceId'], isNotEmpty);
    expect(body['clientPunchId'], isNotEmpty);
    // Full-screen success like a UPI payment, then back to the button.
    expect(find.byKey(const Key('successOnline')), findsOneWidget);
    expect(find.text('Checked in!'), findsOneWidget);
    expect(find.text('Sharma Medical · 11 m'), findsOneWidget);
    await tester.tap(find.byKey(const Key('successDone')));
    await tester.pumpAndSettle();
    expect(find.text('Check out'), findsOneWidget);
    expect(queue.length, 0);
  });

  testWidgets('offline check-in is queued, announced and reflected in the button', (tester) async {
    final api = await pumpHome(tester);
    api.error = ApiException.network();

    await tester.tap(find.byKey(const Key('checkInButton')));
    await tester.pumpAndSettle();

    expect(queue.length, 1);
    expect(queue.pending.single.type, 'in');
    expect(find.byKey(const Key('successOffline')), findsOneWidget);
    expect(find.text('Saved offline'), findsOneWidget);
    expect(find.textContaining('Will sync when internet is back'), findsOneWidget);
    await tester.tap(find.byKey(const Key('successDone')));
    await tester.pumpAndSettle();
    expect(find.text('Check out'), findsOneWidget);
    expect(find.byKey(const Key('pendingSyncBanner')), findsOneWidget);
    expect(find.text('1 punch(es) waiting to sync'), findsOneWidget);
  });

  testWidgets('outside geofence shows a clear explanation and queues nothing', (tester) async {
    final api = await pumpHome(tester);
    api.error = const ApiException(
      code: ApiErrorCode.outsideGeofence,
      message: 'You are 350 m from Sharma Medical',
      statusCode: 422,
    );

    await tester.tap(find.byKey(const Key('checkInButton')));
    await tester.pumpAndSettle();

    expect(find.text('You are outside the shop area'), findsOneWidget);
    expect(find.textContaining('350 m'), findsOneWidget);
    expect(queue.length, 0);
    expect(find.text('Check in'), findsOneWidget);
  });

  group('CheckInButton', () {
    Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );

    testWidgets('labels follow the state', (tester) async {
      await pump(tester, CheckInButton(state: PunchButtonState.checkIn, onPressed: () {}));
      expect(find.text('Check in'), findsOneWidget);
      await pump(tester, CheckInButton(state: PunchButtonState.checkOut, onPressed: () {}));
      expect(find.text('Check out'), findsOneWidget);
      await pump(tester, CheckInButton(state: PunchButtonState.completed, onPressed: () {}));
      expect(find.text('Check in again'), findsOneWidget);
    });

    testWidgets('busy state shows progress and ignores taps', (tester) async {
      var taps = 0;
      await pump(
        tester,
        CheckInButton(
          state: PunchButtonState.checkIn,
          busy: true,
          busyLabel: 'Getting your location…',
          onPressed: () => taps++,
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Getting your location…'), findsOneWidget);
      await tester.tap(find.byKey(const Key('checkInButton')));
      await tester.pump();
      expect(taps, 0);
      final button = tester.widget<ElevatedButton>(find.byKey(const Key('checkInButton')));
      expect(button.onPressed, isNull);
    });

    testWidgets('renders in Hindi', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('hi'),
          supportedLocales: const [Locale('en'), Locale('hi')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: CheckInButton(state: PunchButtonState.checkIn, onPressed: () {}),
          ),
        ),
      );
      expect(find.text('हाज़िरी लगाएँ'), findsOneWidget);
      expect(find.text('Check in · 1 tap'), findsOneWidget);
    });
  });
}
