import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:staffmint/core/api/providers.dart';
import 'package:staffmint/core/api/services/geo_api.dart';
import 'package:staffmint/core/storage/providers.dart';
import 'package:staffmint/core/widgets/location_picker.dart';

class _FakeGeoApi implements GeoApi {
  final searched = <String>[];

  @override
  Future<List<GeoPlace>> search(String q, {double? lat, double? lng, String? lang}) async {
    searched.add(q);
    if (q.contains('zzz')) return [];
    return const [
      GeoPlace(
        name: 'Karol Bagh Market',
        address: 'Ajmal Khan Road, Karol Bagh, New Delhi',
        lat: 28.6514,
        lng: 77.1907,
      ),
    ];
  }

  @override
  Future<String?> reverse(double lat, double lng, {String? lang}) async => 'Connaught Place, New Delhi';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'sm_language': 'en'});
    prefs = await SharedPreferences.getInstance();
  });

  Future<_FakeGeoApi> pump(WidgetTester tester, Widget child) async {
    final api = _FakeGeoApi();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs), geoApiProvider.overrideWithValue(api)],
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await tester.pump();
    return api;
  }

  testWidgets('no pin yet: a clear "Set your shop location" card with Find on map', (tester) async {
    await pump(tester, LocationPicker(value: null, onChanged: (_) {}));
    expect(find.text('Set your shop location'), findsOneWidget);
    expect(find.text('Find on map'), findsOneWidget);
    expect(find.text('Use my current location'), findsOneWidget);
  });

  testWidgets('map picker: search a market, pick it, and the address comes back with the pin', (tester) async {
    LatLng? pin;
    String? address;
    final api = await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => ListView(
          children: [
            LocationPicker(
              value: pin,
              address: address,
              radiusM: 100,
              onChanged: (p) => setState(() => pin = p),
              onAddress: (a) => setState(() => address = a),
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('openMapPicker')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Shop location'), findsOneWidget);
    expect(find.text('Move the map to put the pin on your shop'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('placeSearch')), 'zzz');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('No places found. Try the market or area name.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('placeSearch')), 'karol');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(api.searched, ['zzz', 'karol']);
    await tester.tap(find.text('Karol Bagh Market'));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Karol Bagh Market, Ajmal Khan Road, Karol Bagh, New Delhi'), findsOneWidget);

    await tester.tap(find.byKey(const Key('useThisLocation')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(pin!.latitude, closeTo(28.6514, 0.0001));
    expect(address, 'Karol Bagh Market, Ajmal Khan Road, Karol Bagh, New Delhi');
    expect(find.text('Change on map'), findsOneWidget);
    expect(find.text('Karol Bagh Market, Ajmal Khan Road, Karol Bagh, New Delhi'), findsOneWidget);
  });

  testWidgets('a pin that was set before shows its address under the map', (tester) async {
    final api = await pump(tester, const MapPickerScreen(initial: LatLng(28.6315, 77.2167), radiusM: 100));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(api.searched, isEmpty);
    expect(find.text('Connaught Place, New Delhi'), findsOneWidget);
    expect(find.text('Use this location'), findsOneWidget);
  });
}
