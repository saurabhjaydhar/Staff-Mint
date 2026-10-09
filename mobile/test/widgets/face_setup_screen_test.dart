import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staffmint/core/api/api_exception.dart';
import 'package:staffmint/core/api/providers.dart';
import 'package:staffmint/core/api/services/me_api.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/core/storage/providers.dart';
import 'package:staffmint/features/auth/auth_controller.dart';
import 'package:staffmint/features/auth/session_state.dart';
import 'package:staffmint/features/employee/face/face_setup_screen.dart';
import 'package:staffmint/features/employee/punch/punch_capture.dart';

class _FakeAuth extends AuthController {
  int refreshes = 0;
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
    company: Company(
      id: 'c1',
      name: 'Sharma Medical',
      businessType: 'pharmacy',
      settings: CompanySettings(faceMatchPolicy: 'review'),
    ),
    employee: Employee(id: 'e1', name: 'Ramesh', phone: '9876543210', locationConsent: true),
  );

  @override
  Future<void> refreshMe({bool? needsCompanySetupHint}) async => refreshes++;
}

class _FakeMeApi implements MeApi {
  _FakeMeApi(this.face);
  FaceInfo face;
  final List<String> enrolled = [];
  int withdrawals = 0;
  ApiException? enrollError;

  @override
  Future<FaceInfo> myFace() async => face;

  @override
  Future<FaceInfo> enrollFace(String photoBase64) async {
    if (enrollError != null) throw enrollError!;
    enrolled.add(photoBase64);
    return face = const FaceInfo(status: 'pending', photoUrl: null);
  }

  @override
  Future<FaceInfo> withdrawFace() async {
    withdrawals++;
    return face = const FaceInfo();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCapture implements PunchCapture {
  final List<bool> liveCalls = [];
  @override
  Future<String?> selfie(BuildContext context, {bool live = false}) async {
    liveCalls.add(live);
    return 'ZmFjZQ==';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late SharedPreferences prefs;
  late _FakeCapture capture;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'sm_language': 'en'});
    prefs = await SharedPreferences.getInstance();
    capture = _FakeCapture();
  });

  Future<void> pump(WidgetTester tester, _FakeMeApi api) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authControllerProvider.overrideWith(_FakeAuth.new),
          meApiProvider.overrideWithValue(api),
          punchCaptureProvider.overrideWithValue(capture),
        ],
        child: const MaterialApp(home: FaceSetupScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('nothing is taken until the person ticks the consent box', (tester) async {
    final api = _FakeMeApi(const FaceInfo());
    await pump(tester, api);

    expect(find.text('Set up face check'), findsOneWidget);
    expect(find.textContaining('If I say no, I can still check in'), findsOneWidget);
    final agree = find.byKey(const Key('faceAgree'));
    expect(tester.widget<ButtonStyleButton>(agree).onPressed, isNull);

    await tester.tap(find.byKey(const Key('faceConsentBox')));
    await tester.pump();
    await tester.tap(agree);
    await tester.pumpAndSettle();

    expect(capture.liveCalls, [true]);
    expect(api.enrolled, ['ZmFjZQ==']);
    expect(find.text('Photo sent to your owner for approval'), findsOneWidget);
    expect(find.text('Waiting for owner approval'), findsOneWidget);
  });

  testWidgets('a photo without a clear face explains what to do', (tester) async {
    final api = _FakeMeApi(const FaceInfo())
      ..enrollError = const ApiException(
        code: 'FACE_NOT_CLEAR',
        message: 'More than one face',
        statusCode: 422,
        details: {'reason': 'many_faces'},
      );
    await pump(tester, api);
    await tester.tap(find.byKey(const Key('faceConsentBox')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('faceAgree')));
    await tester.pumpAndSettle();
    expect(find.text('Only you in the photo'), findsOneWidget);
    expect(find.text('Set up face check'), findsOneWidget);
  });

  testWidgets('approved photo can be removed, which withdraws consent', (tester) async {
    final api = _FakeMeApi(const FaceInfo(status: 'approved'));
    await pump(tester, api);
    expect(find.text('Face check is on'), findsOneWidget);

    await tester.tap(find.byKey(const Key('faceRemove')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your photo will be deleted'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await tester.pumpAndSettle();

    expect(api.withdrawals, 1);
    expect(find.text('Face photo removed'), findsOneWidget);
    // Back to the consent form.
    expect(find.byKey(const Key('faceConsentBox')), findsOneWidget);
  });
}
