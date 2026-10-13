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
