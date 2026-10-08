import 'package:geolocator/geolocator.dart';

class LocationException implements Exception {
  const LocationException({this.serviceDisabled = false, this.permanentlyDenied = false});
  final bool serviceDisabled;
  final bool permanentlyDenied;
  @override
  String toString() =>
      'LocationException(serviceDisabled: $serviceDisabled, '
      'permanentlyDenied: $permanentlyDenied)';
}

/// Geolocator wrapper: permission handling + a single high-accuracy fix.
class LocationService {
  LocationService._();

  static Future<void> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(serviceDisabled: true);
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) throw const LocationException();
    if (perm == LocationPermission.deniedForever) {
      throw const LocationException(permanentlyDenied: true);
    }
  }

  /// Current position (falls back to last known if a fresh fix times out).
  static Future<Position> current({Duration timeout = const Duration(seconds: 15)}) async {
    await ensurePermission();
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.high, timeLimit: timeout),
      );
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return last;
      rethrow;
    }
  }
}
