import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:staffmint/core/storage/providers.dart';
import 'package:staffmint/features/owner/staff/contact_rows.dart';
import 'package:staffmint/features/owner/staff/contacts_picker_screen.dart';

void main() {
  testWidgets('picker shows all contacts, counts them, greys out non-mobiles, and returns the ticked ones', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'sm_language': 'en'});
    final prefs = await SharedPreferences.getInstance();
    final rows = buildContactRows([
      ('Raju', [('98765 43210', null)]),
      ('Pooja', [('0091 98765 00003', null)]),
      ('Shop landline', [('022 2345 6789', null)]),
    ]);
    List<PickedContact>? picked;
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => picked = await Navigator.of(context).push<List<PickedContact>>(
                  MaterialPageRoute(builder: (_) => ContactsPickerScreen(loadContacts: () async => (rows, true))),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('3 contacts · 2 can be added'), findsOneWidget);
    expect(find.byKey(const Key('contactsLimited')), findsOneWidget);
    expect(find.text('Pooja'), findsOneWidget);
    expect(find.text('Can’t be added (no mobile number)'), findsOneWidget);
    expect(find.text('022 2345 6789 · Not a mobile number'), findsOneWidget);

    await tester.tap(find.byKey(const Key('contact_9876500003')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('contactsAdd')));
    await tester.pumpAndSettle();
    expect(picked!.single.phone, '9876500003');
    expect(picked!.single.name, 'Pooja');
  });
}
