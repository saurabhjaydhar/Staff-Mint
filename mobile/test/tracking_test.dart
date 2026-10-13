import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staffmint/core/api/api_exception.dart';
import 'package:staffmint/core/api/providers.dart';
import 'package:staffmint/core/api/services/tracking_api.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/core/storage/providers.dart';
import 'package:staffmint/core/utils/json.dart';
import 'package:staffmint/features/tracking/tracking_controller.dart';
import 'package:staffmint/features/tracking/tracking_engine.dart';
import 'package:staffmint/features/tracking/tracking_widgets.dart';
import 'package:staffmint/features/tracking/field_staff_screens.dart';
import 'package:staffmint/core/widgets/track_map.dart';

class _Source implements LocationSource {
  final fixesCtl = StreamController<TrackFix>.broadcast();
  final serviceCtl = StreamController<bool>.broadcast();
  int started = 0;
  String? title;

  @override
  Stream<TrackFix> fixes({
    required int intervalSec,
    required int distanceM,
    required String title,
    required String text,
  }) {
    started++;
    this.title = title;
    return fixesCtl.stream;
  }

  @override
  Stream<bool> serviceChanges() => serviceCtl.stream;
}

class _Api implements TrackingApi {
  final sent = <List<Json>>[];
  final sentEvents = <String>[];
  bool offline = false;
  PingResult answer = const PingResult(accepted: 1);
  MyTracking state = const MyTracking(
    businessName: 'Sharma Medical',
    enabled: true,
    consentEn: ['Only while you are checked in.'],
  );
  ({bool enabled, bool consented}) setResult = (enabled: true, consented: false);

  @override
  Future<PingResult> pings(List<Json> points) async {
    if (offline) throw const ApiException(code: ApiErrorCode.network, message: 'offline');
    sent.add(points);
    return answer;
  }

  @override
  Future<void> events(List<Json> list) async => sentEvents.addAll([for (final e in list) '${e['type']}']);
  @override
  Future<MyTracking> me() async => state;
  @override
  Future<MyTracking> consent() async {
    state = MyTracking(businessName: state.businessName, enabled: true, consented: true, consentEn: state.consentEn);
    return state;
  }

  @override
  Future<MyTracking> withdraw() async {
    state = MyTracking(businessName: state.businessName, enabled: true, consentEn: state.consentEn);
    return state;
  }

  @override
  Future<({bool enabled, bool consented})> setFor(String employeeId, bool enabled) async => setResult;

  List<LiveStaff> liveList = const [];
  TrackDay? dayResult;
  final dayCalls = <String>[];

  @override
  Future<List<LiveStaff>> live() async => liveList;

  @override
  Future<TrackDay> day(String date, {String? employeeId}) async {
    dayCalls.add('${employeeId ?? 'me'}:$date');
    return dayResult ?? TrackDay(name: 'Raju', date: date);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TrackFix _fix(int i) => TrackFix(at: DateTime(2026, 10, 13, 10, i), lat: 28.6 + i / 1000, lng: 77.2, accuracyM: 10);

void main() {
  group('engine', () {
    test('keeps points on the phone and sends them in batches of 20', () async {
      final api = _Api();
      final source = _Source();
      final buffer = MemoryPointBuffer();
      final e = TrackingEngine(api: api, source: source, buffer: buffer, flushAt: 20);
      await e.start(const MyTracking(shouldShare: true), title: 'T', text: 'x');
      expect(e.running, isTrue);
      // The first point goes at once.
      source.fixesCtl.add(_fix(0));
      await pumpEventQueue();
      expect(api.sent.single, hasLength(1));
      for (var i = 1; i < 20; i++) {
        source.fixesCtl.add(_fix(i));
      }
      await pumpEventQueue();
      expect(api.sent, hasLength(1));
      expect(e.pending, 19);
      source.fixesCtl.add(_fix(20));
      await pumpEventQueue();
      expect(api.sent.last, hasLength(20));
      expect(e.pending, 0);
      await e.dispose();
    });

    test('without signal the points wait; the server saying stop ends sharing', () async {
      final api = _Api()..offline = true;
      final source = _Source();
      final e = TrackingEngine(api: api, source: source, buffer: MemoryPointBuffer());
      await e.start(const MyTracking(shouldShare: true), title: 'T', text: 'x');
      source.fixesCtl
        ..add(_fix(1))
        ..add(_fix(2));
      await pumpEventQueue();
      await e.flush();
      expect(e.pending, 2);
      api
        ..offline = false
        ..answer = const PingResult(stop: true, reason: 'checked_out');
      await e.flush();
      expect(api.sent.single, hasLength(2));
      expect(e.running, isFalse);
      expect(e.pending, 0);
    });

    test('points wait while a check-in is still offline; location off is reported', () async {
      final api = _Api();
      final source = _Source();
      var pendingPunch = true;
      final e = TrackingEngine(
        api: api,
        source: source,
        buffer: MemoryPointBuffer(),
        punchesPending: () => pendingPunch,
      );
      await e.start(const MyTracking(shouldShare: true), title: 'T', text: 'x');
      source.fixesCtl.add(_fix(1));
      source.serviceCtl.add(false);
      await pumpEventQueue();
      await e.flush();
      expect(api.sent, isEmpty);
      expect(api.sentEvents, ['location_off']);
      pendingPunch = false;
      await e.flush();
      expect(api.sent.single, hasLength(1));
      await e.dispose();
    });
  });

  setUpAll(() => TrackMap.showTiles = false);

  group('screens', () {
    Future<(_Api, _Source)> pump(WidgetTester tester, Widget child, {String lang = 'en', _Api? api}) async {
      SharedPreferences.setMockInitialValues({'sm_language': lang});
      final prefs = await SharedPreferences.getInstance();
      final a = api ?? _Api();
      final source = _Source();
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            trackingApiProvider.overrideWithValue(a),
            locationSourceProvider.overrideWithValue(source),
            pointBufferProvider.overrideWithValue(MemoryPointBuffer()),
          ],
          child: MaterialApp(
            locale: Locale(lang),
            supportedLocales: const [Locale('en'), Locale('hi')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(body: child),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (a, source);
    }

    testWidgets('staff: the owner asked → read and agree; the home shows it is not sharing yet', (tester) async {
      final (api, _) = await pump(tester, const _Refresh(child: _List()));
      expect(find.text('Share location during work?'), findsOneWidget);
      expect(find.text('Sharma Medical asked. Only while you are checked in.'), findsOneWidget);
      expect(find.text('Your employer asked. Tap to read.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('trackRead')));
      await tester.pumpAndSettle();
      expect(find.text('Only while you are checked in.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('trackAgree')));
      await tester.pumpAndSettle();
      expect(api.state.consented, isTrue);
      expect(find.text('Thanks. Sharing starts when you check in.'), findsOneWidget);
      expect(find.text('Share location during work?'), findsNothing);
      expect(find.text('On while checked in'), findsOneWidget);
    });

    testWidgets('staff can stop sharing from their profile', (tester) async {
      final api = _Api()..state = const MyTracking(businessName: 'Sharma Medical', enabled: true, consented: true);
      await pump(tester, const _Refresh(child: TrackingProfileTile()), api: api);
      await tester.tap(find.byKey(const Key('trackStop')));
      await tester.pumpAndSettle();
      expect(find.text('Your employer will be told. You can agree again later.'), findsOneWidget);
      await tester.tap(find.text('Confirm').last);
      await tester.pumpAndSettle();
      expect(api.state.consented, isFalse);
      expect(find.text('Location sharing stopped'), findsOneWidget);
    });

    testWidgets('owner: field staff switch shows who still has to agree', (tester) async {
      var changed = 0;
      await pump(
        tester,
        FieldStaffSwitch(
          employee: const Employee(id: 'e1', name: 'Raju', phone: '9876543210'),
          onChanged: () => changed++,
        ),
      );
      expect(find.text('See where they are while checked in'), findsOneWidget);
      await tester.tap(find.byKey(const Key('fieldStaffSwitch')));
      await tester.pumpAndSettle();
      expect(find.text('Waiting for Raju to agree'), findsOneWidget);
      expect(changed, 1);
    });

    testWidgets('owner: field staff on the map with how long ago, where and km; tap opens their day', (tester) async {
      final now = DateTime.now();
      final api = _Api()
        ..liveList = [
          LiveStaff(
            employeeId: 'e1',
            name: 'Raju Kumar',
            status: 'live',
            lastPingAt: now.subtract(const Duration(minutes: 3)),
            lat: 28.65,
            lng: 77.19,
            distanceM: 18200,
            near: 'Ajmal Khan Road, Karol Bagh',
          ),
          const LiveStaff(employeeId: 'e2', name: 'Amit', status: 'waiting_consent'),
        ]
        ..dayResult = TrackDay(
          name: 'Raju Kumar',
          date: '2026-10-13',
          distanceM: 18200,
          route: [
            TrackPoint(at: now, lat: 28.63, lng: 77.21),
            TrackPoint(at: now, lat: 28.65, lng: 77.19),
          ],
          stops: [
            TrackStop(
              lat: 28.65,
              lng: 77.19,
              from: DateTime(2026, 10, 13, 10, 12),
              to: DateTime(2026, 10, 13, 10, 40),
              minutes: 28,
              place: 'Ajmal Khan Road, Karol Bagh',
            ),
          ],
          punches: [(type: 'in', at: TrackPoint(at: DateTime(2026, 10, 13, 9, 2), lat: 28.63, lng: 77.21))],
        );
      await pump(tester, const FieldStaffMapScreen(), api: api);
      expect(find.byKey(const Key('liveMap')), findsOneWidget);
      expect(find.text('3 min ago · near Ajmal Khan Road, Karol Bagh · 18 km'), findsOneWidget);
      expect(find.text('Hasn’t agreed yet'), findsOneWidget);
      await tester.tap(find.byKey(const Key('live_e1')));
      await tester.pumpAndSettle();
      expect(api.dayCalls.single, startsWith('e1:'));
      expect(find.text('18 km'), findsOneWidget);
      expect(find.text('Ajmal Khan Road, Karol Bagh'), findsOneWidget);
      expect(find.text('10:12 AM – 10:40 AM · 28 min'), findsOneWidget);
      // Yesterday.
      await tester.tap(find.byKey(const Key('dayPrev')));
      await tester.pumpAndSettle();
      expect(api.dayCalls, hasLength(2));
    });

    testWidgets('owner: no field staff yet', (tester) async {
      await pump(tester, const FieldStaffMapScreen());
      expect(find.textContaining('No field staff yet'), findsOneWidget);
    });

    testWidgets('Hindi consent', (tester) async {
      final api = _Api()
        ..state = const MyTracking(businessName: 'शर्मा मेडिकल', enabled: true, consentHi: ['सिर्फ़ चेक-इन रहते हुए।']);
      await pump(
        tester,
        const _Refresh(child: TrackingHomeCard()),
        lang: 'hi',
        api: api,
      );
      expect(find.text('काम के दौरान लोकेशन शेयर करें?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('trackRead')));
      await tester.pumpAndSettle();
      expect(find.text('सिर्फ़ चेक-इन रहते हुए।'), findsOneWidget);
      expect(find.text('मैं सहमत हूँ'), findsOneWidget);
    });
  });
}

/// Loads "should I share?" once, like the staff home does.
class _Refresh extends ConsumerStatefulWidget {
  const _Refresh({required this.child});
  final Widget child;
  @override
  ConsumerState<_Refresh> createState() => _RefreshState();
}

class _RefreshState extends ConsumerState<_Refresh> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(trackingControllerProvider.notifier).refresh(title: 'T', text: 'x'));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _List extends StatelessWidget {
  const _List();
  @override
  Widget build(BuildContext context) => ListView(children: const [TrackingHomeCard(), TrackingProfileTile()]);
}
