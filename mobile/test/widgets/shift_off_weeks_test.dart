import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staffmint/core/api/providers.dart';
import 'package:staffmint/core/api/services/company_api.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/core/storage/providers.dart';
import 'package:staffmint/core/utils/json.dart';
import 'package:staffmint/features/owner/more/shifts_screen.dart';

const _shop = Shift(id: 's1', name: 'Shop', start: '09:00', end: '18:00', weeklyOff: [0, 6]);

class _FakeCompanyApi implements CompanyApi {
  final updates = <Json>[];
  @override
  Future<List<Shift>> shifts() async => [_shop];
  @override
  Future<Shift> updateShift(String id, Json partial) async {
    updates.add(partial);
    return _shop;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('a shift can have the 1st and 3rd Saturday off', (tester) async {
    SharedPreferences.setMockInitialValues({'sm_language': 'en'});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final api = _FakeCompanyApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs), companyApiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: [Locale('en'), Locale('hi')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: ShiftsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('9:00 AM – 6:00 PM\nWeekly off: Sunday, Saturday'), findsOneWidget);
    await tester.tap(find.text('Shop'));
    await tester.pumpAndSettle();
    expect(find.text('Which Saturdays off?'), findsOneWidget);
    expect(find.text('Which Sundays off?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('offWeeks_6_1_3')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(api.updates.single['weeklyOff'], [0, 6]);
    expect(api.updates.single['weeklyOffWeeks'], {
      '6': [1, 3],
    });
  });
}
