import '../../utils/json.dart';
import '../api_client.dart';

/// A place found by name (shop, market, area).
class GeoPlace {
  const GeoPlace({required this.name, required this.address, required this.lat, required this.lng});
  final String name;
  final String address;
  final double lat;
  final double lng;

  factory GeoPlace.fromJson(Json j) => GeoPlace(
    name: asString(j['name']),
    address: asString(j['address']),
    lat: asDouble(j['lat']),
    lng: asDouble(j['lng']),
  );
}

/// Place search and pin → address, through our server (the Maps key never ships in the app).
class GeoApi {
  GeoApi(this._c);
  final ApiClient _c;

  Future<List<GeoPlace>> search(String q, {double? lat, double? lng, String? lang}) async =>
      asList(await _c.get('/geo/search', query: {'q': q, 'lat': ?lat, 'lng': ?lng, 'lang': ?lang}), GeoPlace.fromJson);

  Future<String?> reverse(double lat, double lng, {String? lang}) async =>
      asStringOrNull(asMap(await _c.get('/geo/reverse', query: {'lat': lat, 'lng': lng, 'lang': ?lang}))['address']);
}
