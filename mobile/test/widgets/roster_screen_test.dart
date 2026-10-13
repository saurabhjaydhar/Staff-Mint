import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staffmint/core/api/api_exception.dart';
import 'package:staffmint/core/api/providers.dart';
import 'package:staffmint/core/api/services/roster_api.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/core/storage/providers.dart';
import 'package:staffmint/features/owner/staff/roster_screen.dart';

typedef _Cell = ({String employeeId, String date, String kind, String? shiftId});

const _shifts = [
  Shift(id: 'm', name: 'Morning', start: '08:00', end: '14:00'),
  Shift(id: 'e', name: 'Evening', start: '14:00', end: '20:00'),
];

const _days = ['2026-10-05', '2026-10-06', '2026-10-07', '2026-10-08', '2026-10-09', '2026-10-10', '2026-10-11'];

RosterWeek _week({bool fixed = false, bool sent = false}) => RosterWeek(
  weekStart: '2026-10-05',
  days: [for (final d in _days) (date: d, holiday: d == '2026-10-09' ? 'Dussehra' : null)],
  shifts: _shifts,
  staff: [
    RosterStaff(
      id: 'raju',
      name: 'Raju',
      designation: 'Helper',
      cells: [
        for (final d in _days)
          d == '2026-10-11'
              ? RosterCell(date: d, kind: 'off')
              : d == '2026-10-06'
              ? RosterCell(date: d, kind: 'shift', shiftId: 'e', usual: false, changed: !sent)
              : RosterCell(date: d, kind: 'shift', shiftId: 'm'),
      ],
    ),
    RosterStaff(
      id: 'sita',
      name: 'Sita',
      cells: [
        for (final d in _days)
          d == '2026-10-06'
              ? RosterCell(
                  date: d,
                  kind: fixed ? 'off' : 'shift',
                  shiftId: fixed ? null : 'm',
                  leave: 'paid',
                  usual: !fixed,
                  changed: fixed,
                )
              : RosterCell(date: d, kind: d == '2026-10-11' ? 'off' : 'shift', shiftId: 'm'),
      ],
    ),
  ],
  notSent: sent ? 0 : (fixed ? 2 : 1),
  problems: fixed
      ? const []
      : const [RosterProblem(type: 'leave_working', employeeId: 'sita', name: 'Sita', date: '2026-10-06')],
);

class _FakeRosterApi implements RosterApi {
  _FakeRosterApi({this.planError = false});
  final bool planError;
  final saved = <List<_Cell>>[];
  final sentWeeks = <String>[];
  var loads = 0;
  var fixed = false;

  @override
  Future<RosterWeek> week(String date) async {
    loads++;
    if (planError) {
      throw const ApiException(code: ApiErrorCode.featureNotInPlan, message: 'Upgrade', statusCode: 402);
    }
    return _week(fixed: fixed, sent: sentWeeks.isNotEmpty);
  }

  @override
  Future<void> setCells(List<_Cell> cells) async {
    saved.add(cells);
    if (cells.any((c) => c.employeeId == 'sita' && c.kind == 'off')) fixed = true;
  }

  @override
  Future<int> send(String week) async {
    sentWeeks.add(week);
    return 2;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, _FakeRosterApi api, {String lang = 'en'}) async {
  SharedPreferences.setMockInitialValues({'sm_language': lang});
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs), rosterApiProvider.overrideWithValue(api)],
      child: MaterialApp(
        locale: Locale(lang),
        supportedLocales: const [Locale('en'), Locale('hi')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: RosterScreen(initialDate: DateTime(2026, 10, 6)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _in(String key, Finder f) => find.descendant(of: find.byKey(Key(key)), matching: f);

void main() {
  testWidgets('one day at a time: who works which shift, leave and unsent changes are clear', (tester) async {
    await _pump(tester, _FakeRosterApi());
    expect(find.text('Roster'), findsOneWidget);
    expect(find.text('1 change not sent to staff yet'), findsOneWidget);
    expect(find.text('Morning 0'), findsNothing);
    expect(find.text('Evening 1 · Day off 1'), findsOneWidget);
    expect(_in('rosterRow_raju', find.text('Evening')), findsOneWidget);
    expect(_in('rosterRow_raju', find.text('2 – 8')), findsOneWidget);
    expect(_in('rosterRow_sita', find.text('On leave')), findsOneWidget);
    // Two shifts already: no tip to add them.
    expect(find.byKey(const Key('rosterShiftsTip')), findsNothing);

    // Sunday: both off. Friday: the holiday is called out.
    await tester.tap(find.byKey(const Key('rosterDay6')));
    await tester.pumpAndSettle();
    expect(_in('rosterRow_raju', find.text('Day off')), findsOneWidget);
    expect(find.text('Day off 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('rosterDay4')));
    await tester.pumpAndSettle();
    expect(find.text('Holiday · Dussehra'), findsOneWidget);
    expect(_in('rosterRow_raju', find.text('Morning')), findsOneWidget);
  });

  testWidgets('change a shift: big choices, same shift all week skips days off', (tester) async {
    final api = _FakeRosterApi();
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('rosterRow_raju')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rosterChangeSheet')), findsOneWidget);
    expect(find.text('8:00 AM – 2:00 PM'), findsOneWidget);
    // Changed by the roster, so "Usual shift" is offered to undo it.
    expect(find.byKey(const Key('rosterPick_usual')), findsOneWidget);

    await tester.tap(find.byKey(const Key('rosterPick_e')));
    await tester.tap(find.byKey(const Key('rosterAllWeek')));
    await tester.pumpAndSettle();
    final loadsBefore = api.loads;
    await tester.tap(find.byKey(const Key('rosterSave')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rosterChangeSheet')), findsNothing);
    final cells = api.saved.single;
    expect(cells.first, (employeeId: 'raju', date: '2026-10-06', kind: 'shift', shiftId: 'e'));
    expect(cells.map((c) => c.date), isNot(contains('2026-10-11')));
    expect(cells, hasLength(6));
    expect(cells.every((c) => c.shiftId == 'e'), isTrue);
    expect(api.loads, greaterThan(loadsBefore));
  });

  testWidgets('day off turns the whole-week switch off; usual sends back to the usual shift', (tester) async {
    final api = _FakeRosterApi();
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('rosterRow_raju')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rosterPick_off')));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('rosterAllWeek'))).onChanged, isNull);
    await tester.tap(find.byKey(const Key('rosterPick_usual')));
    await tester.tap(find.byKey(const Key('rosterSave')));
    await tester.pumpAndSettle();
    expect(api.saved.single, [(employeeId: 'raju', date: '2026-10-06', kind: 'usual', shiftId: null)]);
  });

  testWidgets('send: fix a problem in one tap, then send to staff', (tester) async {
    final api = _FakeRosterApi();
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('rosterSend')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rosterSendSheet')), findsOneWidget);
    expect(find.text('1 thing to fix first'), findsOneWidget);
    expect(find.text('Sita is on leave on Tue'), findsOneWidget);
    expect(find.text('Send to 1 staff'), findsOneWidget);

    await tester.tap(find.byKey(const Key('rosterFix_sita_2026-10-06')));
    await tester.pumpAndSettle();
    expect(api.saved.single, [(employeeId: 'sita', date: '2026-10-06', kind: 'off', shiftId: null)]);
    expect(find.text('1 thing to fix first'), findsNothing);
    expect(find.text('Send to 2 staff'), findsOneWidget);

    await tester.tap(find.byKey(const Key('rosterSendNow')));
    await tester.pumpAndSettle();
    expect(api.sentWeeks, ['2026-10-05']);
    expect(find.byKey(const Key('rosterSendSheet')), findsNothing);
    expect(find.text('Sent to 2 staff'), findsOneWidget);
    expect(find.text('Staff have this week'), findsOneWidget);
  });

  testWidgets('without a paid plan: a clear way to see plans', (tester) async {
    await _pump(tester, _FakeRosterApi(planError: true));
    expect(find.byKey(const Key('rosterNeedsPlan')), findsOneWidget);
    expect(find.text('Roster comes with Starter and up.'), findsOneWidget);
    expect(find.byKey(const Key('rosterSend')), findsNothing);
  });

  testWidgets('Hindi: the day, the sheet and the send button read in Hindi', (tester) async {
    await _pump(tester, _FakeRosterApi(), lang: 'hi');
    expect(find.text('रोस्टर'), findsOneWidget);
    expect(find.text('1 बदलाव अभी स्टाफ़ को नहीं भेजा'), findsOneWidget);
    expect(find.text('स्टाफ़ को भेजें'), findsOneWidget);
    expect(_in('rosterRow_sita', find.text('छुट्टी पर')), findsOneWidget);
    await tester.tap(find.byKey(const Key('rosterSend')));
    await tester.pumpAndSettle();
    expect(find.text('स्टाफ़ को शिफ़्ट भेजें?'), findsOneWidget);
    expect(find.text('छुट्टी करें'), findsOneWidget);
  });
}
