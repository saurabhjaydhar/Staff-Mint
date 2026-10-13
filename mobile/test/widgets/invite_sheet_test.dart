import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/core/storage/providers.dart';
import 'package:staffmint/features/owner/staff/invite_sheet.dart';

Future<void> _open(WidgetTester tester, RemindResult r) async {
  SharedPreferences.setMockInitialValues({'sm_language': 'en'});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => showInviteSheet(context, r), child: const Text('open')),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

const _raju = InvitePerson(name: 'Raju', phone: '+919876500004', status: 'sent', shareText: 'Namaste Raju');
const _pooja = InvitePerson(name: 'Pooja', phone: '+919876500003', status: 'recent', shareText: 'Namaste Pooja');

void main() {
  testWidgets('WhatsApp not set up: says the invite can’t reach them; each person has their own WhatsApp button', (
    tester,
  ) async {
    await _open(tester, const RemindResult(sent: 1, whatsappConnected: false, people: [_raju, _pooja]));
    expect(find.text('App invites'), findsOneWidget);
    expect(find.textContaining('isn’t set up for your business yet'), findsOneWidget);
    expect(find.text('Raju'), findsOneWidget);
    expect(find.text('+91 98765 00004'), findsOneWidget);
    expect(find.byKey(const Key('inviteWa_+919876500004')), findsOneWidget);
    expect(find.byKey(const Key('inviteWa_+919876500003')), findsOneWidget);
  });

  testWidgets('connected: what happened to each invite, failures in red with a way to send them', (tester) async {
    await _open(
      tester,
      const RemindResult(
        sent: 1,
        failed: 1,
        people: [
          _raju,
          _pooja,
          InvitePerson(name: 'Amit', phone: '+919876500006', status: 'failed', shareText: 'x'),
        ],
      ),
    );
    expect(find.textContaining('Some invites couldn’t be sent'), findsOneWidget);
    expect(find.text('+91 98765 00004 · Sent on WhatsApp'), findsOneWidget);
    expect(find.text('+91 98765 00003 · Sent a few minutes ago'), findsOneWidget);
    expect(find.text('+91 98765 00006 · Couldn’t send'), findsOneWidget);
  });
}
