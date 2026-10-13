import '../utils/json.dart';

/// Staff phone: should it share location now, how often, and the consent words.
class MyTracking {
  const MyTracking({
    this.businessName = '',
    this.enabled = false,
    this.consented = false,
    this.shouldShare = false,
    this.sharing = false,
    this.endsBy,
    this.distanceM = 0,
    this.intervalSec = 120,
    this.minDistanceM = 100,
    this.consentEn = const [],
    this.consentHi = const [],
  });
  final String businessName;

  /// The owner made them field staff.
  final bool enabled;
  final bool consented;

  /// Enabled, agreed and checked in: the phone should be sharing.
  final bool shouldShare;
  final bool sharing;
  final DateTime? endsBy;
  final int distanceM;
  final int intervalSec;
  final int minDistanceM;
  final List<String> consentEn;
  final List<String> consentHi;

  /// The owner asked and the person hasn't answered yet.
  bool get needsConsent => enabled && !consented;

  factory MyTracking.fromJson(Json j) {
    final t = asMap(j['consentText']);
    return MyTracking(
      businessName: asString(j['businessName']),
      enabled: asBool(j['enabled']),
      consented: asBool(j['consented']),
      shouldShare: asBool(j['shouldShare']),
      sharing: asBool(j['sharing']),
      endsBy: DateTime.tryParse(asString(j['endsBy']))?.toLocal(),
      distanceM: asInt(j['distanceM']),
      intervalSec: asInt(j['intervalSec'], 120),
      minDistanceM: asInt(j['minDistanceM'], 100),
      consentEn: [for (final x in (t['en'] as List? ?? const [])) '$x'],
      consentHi: [for (final x in (t['hi'] as List? ?? const [])) '$x'],
    );
  }
}

/// The server's answer to a batch of points. [stop]: checked out, shift over, or sharing turned off.
class PingResult {
  const PingResult({this.accepted = 0, this.stop = false, this.reason});
  final int accepted;
  final bool stop;
  final String? reason;

  factory PingResult.fromJson(Json j) =>
      PingResult(accepted: asInt(j['accepted']), stop: asBool(j['stop']), reason: asStringOrNull(j['reason']));
}

/// Owner: one field staff member on the live map.
class LiveStaff {
  const LiveStaff({
    required this.employeeId,
    required this.name,
    required this.status,
    this.lastPingAt,
    this.lat,
    this.lng,
    this.distanceM = 0,
    this.near,
    this.battery,
  });
  final String employeeId;
  final String name;

  /// waiting_consent · not_started · live (< 5 min) · recent (< 15) · stale · ended
  final String status;
  final DateTime? lastPingAt;
  final double? lat;
  final double? lng;
  final int distanceM;
  final String? near;
  final int? battery;

  bool get onMap => lat != null && lng != null;

  factory LiveStaff.fromJson(Json j) => LiveStaff(
    employeeId: asString(j['employeeId']),
    name: asString(j['name']),
    status: asString(j['status'], 'not_started'),
    lastPingAt: DateTime.tryParse(asString(j['lastPingAt']))?.toLocal(),
    lat: (j['lat'] as num?)?.toDouble(),
    lng: (j['lng'] as num?)?.toDouble(),
    distanceM: asInt(j['distanceM']),
    near: asStringOrNull(j['near']),
    battery: asIntOrNull(j['battery']),
  );
}

class TrackPoint {
  const TrackPoint({required this.at, required this.lat, required this.lng});
  final DateTime at;
  final double lat;
  final double lng;

  factory TrackPoint.fromJson(Json j) => TrackPoint(
    at: DateTime.tryParse(asString(j['at']))?.toLocal() ?? DateTime.now(),
    lat: (j['lat'] as num).toDouble(),
    lng: (j['lng'] as num).toDouble(),
  );
}

class TrackStop {
  const TrackStop({
    required this.lat,
    required this.lng,
    required this.from,
    required this.to,
    required this.minutes,
    this.place,
  });
  final double lat;
  final double lng;
  final DateTime from;
  final DateTime to;
  final int minutes;
  final String? place;

  factory TrackStop.fromJson(Json j) => TrackStop(
    lat: (j['lat'] as num).toDouble(),
    lng: (j['lng'] as num).toDouble(),
    from: DateTime.tryParse(asString(j['from']))?.toLocal() ?? DateTime.now(),
    to: DateTime.tryParse(asString(j['to']))?.toLocal() ?? DateTime.now(),
    minutes: asInt(j['minutes']),
    place: asStringOrNull(j['place']),
  );
}

/// One person's day: route, stops, check-in/out and distance.
class TrackDay {
  const TrackDay({
    required this.name,
    required this.date,
    this.distanceM = 0,
    this.route = const [],
    this.stops = const [],
    this.punches = const [],
  });
  final String name;
  final String date;
  final int distanceM;
  final List<TrackPoint> route;
  final List<TrackStop> stops;

  /// Check-in and check-out with where they happened.
  final List<({String type, TrackPoint at})> punches;

  factory TrackDay.fromJson(Json j) => TrackDay(
    name: asString(j['name']),
    date: asString(j['date']),
    distanceM: asInt(j['distanceM']),
    route: asList(j['route'], TrackPoint.fromJson),
    stops: asList(j['stops'], TrackStop.fromJson),
    punches: [
      for (final p in (j['punches'] as List? ?? const []))
        (type: asString(asMap(p)['type']), at: TrackPoint.fromJson(asMap(p))),
    ],
  );
}
