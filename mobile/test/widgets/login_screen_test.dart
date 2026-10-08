import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staffmint/app.dart';
import 'package:staffmint/core/api/providers.dart';
import 'package:staffmint/core/api/services/auth_api.dart';
import 'package:staffmint/core/storage/key_value_store.dart';
import 'package:staffmint/core/storage/providers.dart';

class FakeAuthApi implements AuthApi {
  final List<String> requested = [];

  @override
  Future<OtpRequestResult> requestOtp(String phone, {String channel = 'sms'}) async {
    requested.add(phone);
    return const OtpRequestResult(requestId: 'req-1', expiresInSec: 300, devCode: '123456');
  }

  @override
  Future<AuthResult> verifyOtp({
    required String phone,
    required String code,
    required String deviceId,
    String? deviceName,
  }) => throw UnimplementedError();

  @override
  Future<void> logout(String refreshToken) async {}
}

void main() {
  late SharedPreferences prefs;
  late FakeAuthApi authApi;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    authApi = FakeAuthApi();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          secureStoreProvider.overrideWithValue(MemoryKeyValueStore()),
          authApiProvider.overrideWithValue(authApi),
        ],
        child: const StaffMintApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('logged-out user lands on the login screen', (tester) async {
    await pumpApp(tester);
    expect(find.text('Welcome to StaffMint'), findsOneWidget);
    expect(find.byKey(const Key('phoneField')), findsOneWidget);
    expect(find.text('Get OTP'), findsOneWidget);
  });

  testWidgets('invalid phone shows a validation error and does not call the API', (tester) async {
    await pumpApp(tester);
    await tester.enterText(find.byKey(const Key('phoneField')), '12345');
    await tester.tap(find.byKey(const Key('getOtpButton')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);
    expect(authApi.requested, isEmpty);
  });

  testWidgets('valid phone requests OTP and shows the dev code hint', (tester) async {
    await pumpApp(tester);
    await tester.enterText(find.byKey(const Key('phoneField')), '98765 43210');
    await tester.tap(find.byKey(const Key('getOtpButton')));
    await tester.pumpAndSettle();
    expect(authApi.requested, ['9876543210']);
    expect(find.text('Enter OTP'), findsOneWidget);
    expect(find.byKey(const Key('devCodeHint')), findsOneWidget);
    expect(find.textContaining('123456'), findsOneWidget);
  });

  testWidgets('language toggle switches the UI to Hindi and persists it', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('हिन्दी'));
    await tester.pumpAndSettle();
    expect(find.text('StaffMint में आपका स्वागत है'), findsOneWidget);
    expect(find.text('OTP पाएँ'), findsOneWidget);
    expect(prefs.getString('sm_language'), 'hi');
  });
}
