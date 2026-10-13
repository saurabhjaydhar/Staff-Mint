import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staffmint/core/api/providers.dart';
import 'package:staffmint/core/api/services/verification_api.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/core/storage/providers.dart';
import 'package:staffmint/features/employee/verify/verify_screen.dart';
import 'package:staffmint/features/owner/staff/verify_card.dart';

const _raju = Employee(id: 'e1', name: 'Raju', phone: '9876543210');

VerifyCheck _c(
  String kind,
  String status, {
  String? name,
  String? last4,
  String? reason,
  Map<String, String> details = const {},
}) => VerifyCheck(
  id: 'c_$kind',
  kind: kind,
  status: status,
  nameOnRecord: name,
  last4: last4,
  overrideReason: reason,
  details: details,
);

class _FakeApi implements VerificationApi {
  OwnerVerification owner = const OwnerVerification(used: 1, limit: 3, extraPricePaise: 14900);
  final calls = <String>[];

  // Staff side: a tiny state machine like the server's.
  bool consented = false;
  final status = {'aadhaar': 'waiting', 'pan': 'waiting', 'bank': 'waiting'};

  MyVerification get me => MyVerification(
    businessName: 'Sharma Medical',
    request: VerifyRequest(
      id: 'r1',
      kinds: const ['aadhaar', 'pan', 'bank'],
      status: 'in_progress',
      consented: consented,
    ),
    checks: [
      for (final k in ['aadhaar', 'pan', 'bank']) _c(k, status[k]!),
    ],
    consentEn: const [
      'Your employer will check your documents against government records.',
      'We never save your full Aadhaar number.',
    ],
    consentHi: const ['आपके मालिक आपके दस्तावेज़ सरकारी रिकॉर्ड से जाँचेंगे।'],
    savedBankLast4: '1234',
    savedBankIfsc: 'SBIN0001234',
  );

  @override
  Future<OwnerVerification> forEmployee(String employeeId) async => owner;
  @override
  Future<OwnerVerification> request(String employeeId, List<String> kinds) async {
    calls.add('request:${kinds.join(',')}');
    owner = OwnerVerification(
      badge: 'asked',
      request: VerifyRequest(id: 'r1', kinds: kinds, status: 'asked'),
      checks: [for (final k in kinds) _c(k, 'waiting')],
      used: 2,
      limit: 3,
    );
    return owner;
  }

  @override
  Future<OwnerVerification> accept(String checkId, String reason) async {
    calls.add('accept:$checkId:$reason');
    return owner;
  }

  @override
  Future<OwnerVerification> askAgain(String checkId) async {
    calls.add('again:$checkId');
    return owner;
  }

  @override
  Future<MyVerification> mine() async => me;
  @override
  Future<MyVerification> consent() async {
    consented = true;
    return me;
  }

  @override
  Future<MyVerification> aadhaarOtp(String aadhaar) async {
    calls.add('otp:$aadhaar');
    status['aadhaar'] = 'otp_sent';
    return me;
  }

  @override
  Future<MyVerification> aadhaarVerify(String otp) async {
    calls.add('verify:$otp');
    status['aadhaar'] = 'verified';
    return me;
  }

  @override
  Future<MyVerification> pan(String pan) async {
    calls.add('pan:$pan');
    status['pan'] = 'verified';
    return me;
  }

  @override
  Future<MyVerification> bank({String? accountNumber, String? ifsc}) async {
    calls.add('bank:${accountNumber ?? 'saved'}');
    status['bank'] = 'verified';
    return me;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, _FakeApi api, Widget child, {String lang = 'en'}) async {
  SharedPreferences.setMockInitialValues({'sm_language': lang});
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs), verificationApiProvider.overrideWithValue(api)],
      child: MaterialApp(
        locale: Locale(lang),
        supportedLocales: const [Locale('en'), Locale('hi')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: ListView(children: [child])),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('owner: "Check now" → pick what to check, see what the plan has left, send', (tester) async {
    final api = _FakeApi();
    await _pump(tester, api, const VerifyCard(employee: _raju));
    expect(find.text('Documents check'), findsOneWidget);
    expect(find.text('Not checked yet'), findsOneWidget);
    await tester.tap(find.byKey(const Key('verifyCheckNow')));
    await tester.pumpAndSettle();
    expect(find.text('Check Raju’s documents'), findsOneWidget);
    expect(find.text('Included in your plan: 2 of 3 left this month'), findsOneWidget);
    expect(find.text('₹1 test to their salary account'), findsOneWidget);
    await tester.tap(find.byKey(const Key('verifyKind_pan')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('verifySend')));
    await tester.pumpAndSettle();
    expect(api.calls, ['request:aadhaar,bank']);
    expect(find.text('Sent to Raju. We’ll tell you when it’s done.'), findsOneWidget);
    expect(find.text('Waiting for Raju to agree'), findsOneWidget);
  });

  testWidgets('owner: no checks left this month, or no plan with checks', (tester) async {
    final api = _FakeApi()..owner = const OwnerVerification(used: 3, limit: 3, extraPricePaise: 14900);
    await _pump(tester, api, const VerifyCard(employee: _raju));
    await tester.tap(find.byKey(const Key('verifyCheckNow')));
    await tester.pumpAndSettle();
    expect(find.text('All 3 checks used this month. More at ₹149 each are coming soon.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('verifySend'))).onPressed, isNull);
  });

  testWidgets('owner: results; a name that doesn’t match can be accepted, "not found" asked again', (tester) async {
    final api = _FakeApi()
      ..owner = OwnerVerification(
        badge: 'needs_attention',
        request: const VerifyRequest(id: 'r1', kinds: ['aadhaar', 'pan', 'bank'], status: 'done', consented: true),
        checks: [
          _c('aadhaar', 'verified', last4: '1234', details: const {'dob': '1995-04-12'}),
          _c('pan', 'mismatch', name: 'Rajesh Kumar Sharma', last4: '234F'),
          _c('bank', 'not_found', last4: '0000'),
        ],
        used: 1,
        limit: 3,
      );
    await _pump(tester, api, const VerifyCard(employee: _raju));
    expect(find.text('Needs your look'), findsOneWidget);
    expect(find.text('Verified · ending 1234 · Born 12 Apr 1995'), findsOneWidget);
    expect(find.text('Name on record: Rajesh Kumar Sharma · ending 234F'), findsOneWidget);
    expect(find.text('Not found · ending 0000'), findsOneWidget);
    await tester.tap(find.byKey(const Key('verifyAccept_pan')));
    await tester.pumpAndSettle();
    expect(find.text('Why is this fine?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('verifyReasonSave')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('verifyAgain_bank')));
    await tester.pumpAndSettle();
    expect(api.calls, ['accept:c_pan:Same person, name written differently', 'again:c_bank']);
    expect(find.text('Asked them to do it again'), findsOneWidget);
  });

  testWidgets('staff: agree first, then Aadhaar OTP, PAN and the saved bank account', (tester) async {
    final api = _FakeApi();
    await _pump(tester, api, const SizedBox(height: 1200, child: VerifyScreen()));
    expect(find.text('Before we start'), findsOneWidget);
    expect(find.text('We never save your full Aadhaar number.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('verifyAllow')));
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 3'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('verifyAadhaar')), '234567891234');
    await tester.tap(find.byKey(const Key('verifySendOtp')));
    await tester.pumpAndSettle();
    expect(find.text('OTP sent to your Aadhaar mobile'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('verifyOtp')), '123456');
    await tester.tap(find.byKey(const Key('verifyOtpGo')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('verifyPan')), 'ABCDE1234F');
    await tester.tap(find.byKey(const Key('verifyPanGo')));
    await tester.pumpAndSettle();
    expect(find.text('Use account ending 1234 (SBIN0001234)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('verifyBankSaved')));
    await tester.pumpAndSettle();
    expect(api.calls, ['otp:234567891234', 'verify:123456', 'pan:ABCDE1234F', 'bank:saved']);
    expect(find.text('All done. Your employer can see the results.'), findsOneWidget);
  });

  testWidgets('staff: Hindi consent', (tester) async {
    await _pump(tester, _FakeApi(), const SizedBox(height: 1200, child: VerifyScreen()), lang: 'hi');
    expect(find.text('शुरू करने से पहले'), findsOneWidget);
    expect(find.text('आपके मालिक आपके दस्तावेज़ सरकारी रिकॉर्ड से जाँचेंगे।'), findsOneWidget);
    expect(find.text('अनुमति दें, शुरू करें'), findsOneWidget);
  });
}
