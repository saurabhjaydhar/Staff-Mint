import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staffmint/core/api/providers.dart';
import 'package:staffmint/core/api/services/profile_api.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/core/storage/providers.dart';
import 'package:staffmint/core/utils/json.dart';
import 'package:staffmint/features/auth/auth_controller.dart';
import 'package:staffmint/features/auth/session_state.dart';
import 'package:staffmint/features/profile/profile_screen.dart';

class _FakeAuth extends AuthController {
  static int refreshes = 0;
  static int logouts = 0;
  @override
  SessionState build() => const SessionState(
    status: SessionStatus.authenticated,
    user: User(id: 'u1', phone: '+919999900001', name: 'Rakesh Sharma', role: UserRole.owner, companyId: 'c1'),
    company: Company(id: 'c1', name: 'Sharma Medical Store', businessType: 'pharmacy'),
  );

  @override
  Future<void> refreshMe({bool? needsCompanySetupHint}) async => refreshes++;

  @override
  Future<void> logout() async => logouts++;
}

Profile _owner({String? email}) => Profile(
  userId: 'u1',
  name: 'Rakesh Sharma',
  phone: '+919999900001',
  role: 'owner',
  email: email,
  companyName: 'Sharma Medical Store',
  businessType: 'pharmacy',
  planName: 'Growth',
  completePercent: email == null ? 33 : 67,
  missing: ['photo', if (email == null) 'email'],
);

const _staff = Profile(
  userId: 'u2',
  name: 'Pooja Singh',
  phone: '+919876500003',
  role: 'employee',
  companyName: 'Sharma Medical Store',
  work: WorkInfo(
    employeeId: 'e3',
    designation: 'Cashier',
    joiningDate: '2026-03-25',
    ratePaise: 1400000,
    shiftStart: '09:00',
    shiftEnd: '21:00',
  ),
  completePercent: 50,
  missing: ['photo', 'bank'],
);

class _FakeProfileApi implements ProfileApi {
  _FakeProfileApi(this.profile);
  Profile profile;
  final List<Json> updates = [];
  final List<Json> banks = [];
  final List<String> photos = [];
  final List<String> calls = [];

  @override
  Future<Profile> get() async => profile;

  @override
  Future<Profile> update(Json patch) async {
    updates.add(patch);
    return profile;
  }

  @override
  Future<BankInfo?> setBank(Json bank) async {
    banks.add(bank);
    return BankInfo(holderName: bank['holderName'] as String, accountLast4: '9012', ifsc: bank['ifsc'] as String?);
  }

  @override
  Future<Profile> setPhoto(String base64Jpeg) async {
    photos.add(base64Jpeg);
    return profile;
  }

  @override
  Future<String?> requestPhoneChange(String phone) async {
    calls.add('request:$phone');
    return '123456';
  }

  @override
  Future<Profile> verifyPhoneChange(String phone, String code) async {
    calls.add('verify:$phone:$code');
    return profile;
  }

  @override
  Future<void> logoutEverywhere() async => calls.add('logoutAll');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePicker implements PhotoPicker {
  final List<ImageSource> sources = [];
  @override
  Future<String?> pick(ImageSource source) async {
    sources.add(source);
    return 'cGhvdG8=';
  }
}

/// Drags the profile list until [f] is built, then brings it on screen.
Future<void> scrollTo(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 20 && f.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
}

void main() {
  late SharedPreferences prefs;
  late _FakePicker picker;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'sm_language': 'en'});
    prefs = await SharedPreferences.getInstance();
    picker = _FakePicker();
    _FakeAuth.refreshes = 0;
    _FakeAuth.logouts = 0;
  });

  Future<_FakeProfileApi> pump(WidgetTester tester, Profile p) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final api = _FakeProfileApi(p);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          authControllerProvider.overrideWith(_FakeAuth.new),
          profileApiProvider.overrideWithValue(api),
          photoPickerProvider.overrideWithValue(picker),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return api;
  }

  testWidgets('owner: hero, completeness chips and business; email is validated before saving', (tester) async {
    final api = await pump(tester, _owner());
    expect(find.byKey(const Key('profileName')), findsOneWidget);
    expect(find.text('Rakesh Sharma'), findsWidgets);
    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('Profile 33% complete'), findsOneWidget);
    expect(find.byKey(const Key('missing_email')), findsOneWidget);
    expect(find.text('Growth'), findsOneWidget);
    expect(find.byKey(const Key('addBank')), findsNothing);

    await tester.tap(find.byKey(const Key('missing_email')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('sheetField')), 'rakesh@');
    await tester.tap(find.byKey(const Key('sheetSave')));
    await tester.pumpAndSettle();
    expect(find.text('Email looks wrong'), findsOneWidget);
    expect(api.updates, isEmpty);

    await tester.enterText(find.byKey(const Key('sheetField')), 'rakesh@example.com');
    await tester.tap(find.byKey(const Key('sheetSave')));
    await tester.pumpAndSettle();
    expect(api.updates.single, {'email': 'rakesh@example.com'});
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('staff: work is read-only; salary account needs the number twice and a valid IFSC', (tester) async {
    final api = await pump(tester, _staff);
    expect(find.text('Staff · Cashier'), findsOneWidget);
    await scrollTo(tester, find.text('Set by your owner. Ask them to change it.'));
    expect(find.text('₹14,000 / month'), findsOneWidget);

    await scrollTo(tester, find.byKey(const Key('addBank')));
    await tester.tap(find.byKey(const Key('addBank')));
    await tester.pumpAndSettle();
    // Holder defaults to the person's name.
    expect(find.widgetWithText(TextFormField, 'Pooja Singh'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('bankAccount')), '123456789012');
    await tester.enterText(find.byKey(const Key('bankAccountConfirm')), '123456789000');
    await tester.enterText(find.byKey(const Key('bankIfsc')), 'SBI123');
    await tester.ensureVisible(find.byKey(const Key('sheetSave')));
    await tester.tap(find.byKey(const Key('sheetSave')));
    await tester.pumpAndSettle();
    expect(find.text('Account numbers don\'t match'), findsOneWidget);
    expect(find.text('Like SBIN0001234'), findsOneWidget);
    expect(api.banks, isEmpty);

    await tester.enterText(find.byKey(const Key('bankAccountConfirm')), '123456789012');
    await tester.enterText(find.byKey(const Key('bankIfsc')), 'sbin0001234');
    await tester.ensureVisible(find.byKey(const Key('sheetSave')));
    await tester.tap(find.byKey(const Key('sheetSave')));
    await tester.pumpAndSettle();
    expect(api.banks.single, {
      'holderName': 'Pooja Singh',
      'accountNumber': '123456789012',
      'ifsc': 'SBIN0001234',
      'upiId': null,
    });
  });

  testWidgets('changing the mobile number goes through a code on the new number', (tester) async {
    final api = await pump(tester, _owner(email: 'r@x.in'));
    await tester.tap(find.byKey(const Key('rowPhone')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('newPhone')), '9876501234');
    await tester.tap(find.byKey(const Key('sheetSave')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Test mode — your code is 123456'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('phoneCode')), '123456');
    await tester.tap(find.byKey(const Key('sheetSave')));
    await tester.pumpAndSettle();
    expect(api.calls, ['request:9876501234', 'verify:9876501234:123456']);
    expect(find.text('Mobile number changed'), findsOneWidget);
    expect(_FakeAuth.refreshes, 1);
  });

  testWidgets('photo from the gallery is uploaded', (tester) async {
    final api = await pump(tester, _owner());
    await tester.tap(find.byKey(const Key('avatarButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('photoGallery')));
    await tester.pumpAndSettle();
    expect(picker.sources, [ImageSource.gallery]);
    expect(api.photos, ['cGhvdG8=']);
  });

  testWidgets('log out of all devices asks first, then signs out', (tester) async {
    final api = await pump(tester, _owner());
    await scrollTo(tester, find.byKey(const Key('rowLogoutAll')));
    await tester.tap(find.byKey(const Key('rowLogoutAll')));
    await tester.pumpAndSettle();
    expect(find.textContaining('every phone and computer'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await tester.pumpAndSettle();
    expect(api.calls, ['logoutAll']);
    expect(_FakeAuth.logouts, 1);
  });
}
