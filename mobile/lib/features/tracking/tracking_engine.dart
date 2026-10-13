import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/services/tracking_api.dart';
import '../../core/models/models.dart';
import '../../core/utils/json.dart';

/// One location fix from the phone.
class TrackFix {
  const TrackFix({
    required this.at,
    required this.lat,
    required this.lng,
    this.accuracyM,
    this.speed,
    this.mock = false,
  });
  final DateTime at;
  final double lat;
  final double lng;
  final double? accuracyM;
  final double? speed;
  final bool mock;

  Json toJson() => {
    'at': at.toUtc().toIso8601String(),
    'lat': lat,
    'lng': lng,
    if (accuracyM != null) 'accuracyM': accuracyM,
    if (speed != null && speed! >= 0) 'speed': speed,
    'mock': mock,
  };
}

/// Where fixes come from; faked in tests.
abstract class LocationSource {
  /// Fixes every [intervalSec] seconds or [distanceM] metres. On Android this runs as a foreground service
  /// with a fixed notification ([title], [text]); on iPhone, iOS shows its location indicator.
  Stream<TrackFix> fixes({
    required int intervalSec,
    required int distanceM,
    required String title,
    required String text,
  });

  /// Location turned on (true) or off (false) on the phone.
  Stream<bool> serviceChanges();
}

class GeolocatorSource implements LocationSource {
  @override
  Stream<TrackFix> fixes({
    required int intervalSec,
    required int distanceM,
    required String title,
    required String text,
  }) {
    final LocationSettings settings = switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: distanceM,
        intervalDuration: Duration(seconds: intervalSec),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: title,
          notificationText: text,
          enableWakeLock: true,
          setOngoing: true,
        ),
      ),
      TargetPlatform.iOS => AppleSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: distanceM,
        activityType: ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      ),
      _ => LocationSettings(accuracy: LocationAccuracy.medium, distanceFilter: distanceM),
    };
    return Geolocator.getPositionStream(locationSettings: settings).map(
      (p) => TrackFix(
        at: p.timestamp,
        lat: p.latitude,
        lng: p.longitude,
        accuracyM: p.accuracy,
        speed: p.speed,
        mock: p.isMocked,
      ),
    );
  }

  @override
  Stream<bool> serviceChanges() {
    try {
      return Geolocator.getServiceStatusStream().map((s) => s == ServiceStatus.enabled);
    } catch (_) {
      return const Stream<bool>.empty();
    }
  }
}

/// Points waiting to be sent; kept on the phone so nothing is lost without signal.
abstract class PointBuffer {
  List<Json> all();
  Future<void> add(Json point);
  Future<void> dropFirst(int n);
  Future<void> clear();
}

class HivePointBuffer implements PointBuffer {
  HivePointBuffer(this._box);
  static const boxName = 'track_points';
  final Box<dynamic> _box;

  @override
  List<Json> all() => [for (final v in _box.values) asMap(v)];
  @override
  Future<void> add(Json point) async => _box.add(point);
  @override
  Future<void> dropFirst(int n) async => _box.deleteAll(_box.keys.take(n).toList());
  @override
  Future<void> clear() async => _box.clear();
}

class MemoryPointBuffer implements PointBuffer {
  final _list = <Json>[];
  @override
  List<Json> all() => List.of(_list);
  @override
  Future<void> add(Json point) async => _list.add(point);
  @override
  Future<void> dropFirst(int n) async => _list.removeRange(0, n.clamp(0, _list.length));
  @override
  Future<void> clear() async => _list.clear();
}

/// Shares location during the shift: collects fixes, keeps them on the phone, and sends them in batches
/// (every [flushEvery] or [flushAt] points). Stops when the server says so (checked out, shift over).
class TrackingEngine {
  TrackingEngine({
    required this.api,
    required this.source,
    required this.buffer,
    this.flushEvery = const Duration(minutes: 5),
    this.flushAt = 20,
    this.punchesPending,
  });

  final TrackingApi api;
  final LocationSource source;
  final PointBuffer buffer;
  final Duration flushEvery;
  final int flushAt;

  /// Check-ins still waiting to reach the server: their points wait too, so they aren't turned down.
  final bool Function()? punchesPending;

  StreamSubscription<TrackFix>? _fixes;
  StreamSubscription<bool>? _service;
  Timer? _timer;
  Future<PingResult?>? _sending;
  bool _sentFirst = false;
  final _changes = StreamController<bool>.broadcast();

  bool get running => _fixes != null;

  /// true when sharing starts, false when it stops.
  Stream<bool> get changes => _changes.stream;

  int get pending => buffer.all().length;

  Future<void> start(MyTracking t, {required String title, required String text}) async {
    if (running) return;
    _sentFirst = false;
    _fixes = source
        .fixes(intervalSec: t.intervalSec, distanceM: t.minDistanceM, title: title, text: text)
        .listen(_onFix, onError: (Object _) => _event('permission_removed'));
    _service = source.serviceChanges().listen((on) => _event(on ? 'location_on' : 'location_off'));
    _timer = Timer.periodic(flushEvery, (_) => flush());
    _changes.add(true);
  }

  Future<void> _onFix(TrackFix f) async {
    await buffer.add(f.toJson());
    // The first point goes at once, so the owner sees them straight after check-in; then in batches.
    if (!_sentFirst || pending >= flushAt) {
      _sentFirst = true;
      await flush();
    }
  }

  Future<void> _event(String type) async {
    try {
      await api.events([
        {'at': DateTime.now().toUtc().toIso8601String(), 'type': type},
      ]);
    } catch (_) {
      // Events are best-effort; the server also notices missing points.
    }
  }

  /// Sends what's waiting. Concurrent calls share one send.
  Future<PingResult?> flush() => _sending ??= _send().whenComplete(() => _sending = null);

  Future<PingResult?> _send() async {
    if (punchesPending?.call() ?? false) return null;
    PingResult? last;
    while (true) {
      final batch = buffer.all().take(100).toList();
      if (batch.isEmpty) return last;
      try {
        last = await api.pings(batch);
      } on ApiException {
        return last; // Offline or server trouble: keep them and try later.
      }
      await buffer.dropFirst(batch.length);
      if (last.stop) {
        await buffer.clear();
        await stop(flushFirst: false);
        return last;
      }
    }
  }

  Future<void> stop({bool flushFirst = true}) async {
    if (flushFirst && running) await flush();
    await _fixes?.cancel();
    await _service?.cancel();
    _timer?.cancel();
    final was = running;
    _fixes = null;
    _service = null;
    _timer = null;
    if (was) _changes.add(false);
  }

  Future<void> dispose() async {
    await stop(flushFirst: false);
    await _changes.close();
  }
}
