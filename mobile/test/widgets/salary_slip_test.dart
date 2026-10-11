import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staffmint/core/api/providers.dart';
import 'package:staffmint/core/api/services/company_api.dart';
import 'package:staffmint/core/api/services/employees_api.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/core/utils/json.dart';
import 'package:staffmint/features/owner/more/statutory_screen.dart';
import 'package:staffmint/features/owner/salary/mark_paid_sheet.dart';
import 'package:staffmint/features/owner/staff/slip_details_sheet.dart';

class _FakeCompanyApi implements CompanyApi {
  Json? saved;

  @override
  Future<StatutorySettings> statutory() async => const StatutorySettings();

  @override
  Future<StatutorySettings> updateStatutory(Json partial) async {
    saved = partial;
    return StatutorySettings.fromJson(partial);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeEmployeesApi implements EmployeesApi {
  Json? saved;

  @override
  Future<EmployeeStatutory> updateStatutory(String id, Json partial) async {
    saved = partial;
    return const EmployeeStatutory();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
  }

  testWidgets('"Have you paid everyone?" asks how and returns method + date', (tester) async {
    bigScreen(tester);
    ({String method, String paidOn})? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () async => answer = await askHowPaid(ctx, staffCount: 3),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Have you paid everyone?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('payMethod_upi')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmPaid')));
    await tester.pumpAndSettle();
    expect(answer?.method, 'upi');
    expect(answer?.paidOn, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
  });

  testWidgets('PF / ESI / PT screen: all off by default, turning PF on saves it', (tester) async {
    bigScreen(tester);
    final api = _FakeCompanyApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [companyApiProvider.overrideWithValue(api)],
        child: const MaterialApp(home: StatutoryScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('pfSwitch'))).value, isFalse);
    await tester.tap(find.byKey(const Key('pfSwitch')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pfNumber')), 'DLCPM1234567000');
    await tester.ensureVisible(find.byKey(const Key('saveStatutory')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saveStatutory')));
    await tester.pumpAndSettle();
    expect(api.saved, containsPair('pfEnabled', true));
    expect(api.saved, containsPair('pfNumber', 'DLCPM1234567000'));
    expect(api.saved, containsPair('esiEnabled', false));
  });

  testWidgets('slip details: PAN is sent only when typed again', (tester) async {
    bigScreen(tester);
    final api = _FakeEmployeesApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [employeesApiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SlipDetailsSheet(
                employeeId: 'e1',
                initial: EmployeeStatutory(uan: '100123456789', panMasked: 'ABXXXXX34F'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('slipCode')), 'SM-014');
    await tester.tap(find.byKey(const Key('slipSave')));
    await tester.pumpAndSettle();
    expect(api.saved, {
      'employeeCode': 'SM-014',
      'uan': '100123456789',
      'esicNumber': null,
      'pfExempt': false,
      'esiExempt': false,
    });
  });
}
