import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staffmint/core/api/providers.dart';
import 'package:staffmint/core/api/services/employees_api.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/core/storage/providers.dart';
import 'package:staffmint/features/owner/today/needs_you_card.dart';

class _FakeEmployeesApi implements EmployeesApi {
  final List<String> calls = [];
  @override
  Future<FaceInfo> approveFace(String id) async {
    calls.add('approve:$id');
    return const FaceInfo(status: 'approved');
  }

  @override
  Future<FaceInfo> resetFace(String id) async {
    calls.add('reset:$id');
    return const FaceInfo();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late SharedPreferences prefs;
  late _FakeEmployeesApi api;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'sm_language': 'en'});
    prefs = await SharedPreferences.getInstance();
    api = _FakeEmployeesApi();
  });

  final dashboard = Dashboard(
    date: '2026-10-09',
    counts: const DashboardCounts(total: 6),
    faceEnrollments: const [
      FaceEnrollment(
        employeeId: 'e7',
        employeeName: 'Kavita Sharma',
        face: FaceInfo(status: 'pending'),
      ),
    ],
    punchApprovals: [
      PunchApprovalItem(
        attendanceId: 'a2',
        employeeName: 'Suresh Yadav',
        facePhotoUrl: 'https://example.test/face.jpg',
        punch: Punch(
          id: 'p2',
          type: 'in',
          clientTime: DateTime(2026, 10, 9, 9, 38),
          insideGeofence: true,
          distanceM: 3,
          selfieUrl: 'https://example.test/selfie.jpg',
          approval: 'pending',
          faceResult: 'mismatch',
          faceSimilarity: 12,
        ),
      ),
    ],
  );

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs), employeesApiProvider.overrideWithValue(api)],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: NeedsYouCard(dashboard: dashboard)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('needsYouCard')));
    await tester.pumpAndSettle();
  }

  testWidgets('a flagged selfie shows the approved photo next to it with the reason', (tester) async {
    await pump(tester);
    expect(find.text('2 things need your OK'), findsOneWidget);
    expect(find.textContaining('Face does not match'), findsOneWidget);
    // Inside the shop: no red "m away" line on a face-only flag.
    expect(find.textContaining('m away'), findsNothing);
    final pair = find.byKey(const Key('photoPair_p2'));
    expect(pair, findsOneWidget);
    expect(find.descendant(of: pair, matching: find.text('Approved photo')), findsOneWidget);
    expect(find.descendant(of: pair, matching: find.text('Today\'s selfie')), findsOneWidget);
  });

  testWidgets('a new face photo is approved, or a new one is asked for', (tester) async {
    await pump(tester);
    final card = find.byKey(const Key('faceEnrollment_e7'));
    expect(find.descendant(of: card, matching: find.text('Face photo to approve')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('Ask for a new photo')), findsOneWidget);

    await tester.tap(find.descendant(of: card, matching: find.text('Approve')));
    await tester.pumpAndSettle();
    expect(api.calls, ['approve:e7']);
    expect(find.byKey(const Key('faceEnrollment_e7')), findsNothing);
  });
}
