import 'package:uuid/uuid.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/services/attendance_api.dart';
import '../../../core/utils/json.dart';
import 'punch_queue.dart';

/// Everything captured at the moment of the punch.
class PunchRequest {
  PunchRequest({
    required this.type,
    required this.clientTime,
    required this.lat,
    required this.lng,
    required this.accuracyM,
    required this.mockLocation,
    required this.deviceId,
    this.selfieBase64,
    this.lockCheck,
    String? clientPunchId,
  }) : clientPunchId = clientPunchId ?? const Uuid().v4();

  final String type; // in | out
  final DateTime clientTime;
  final double lat;
  final double lng;
  final double accuracyM;
  final bool mockLocation;
  final String deviceId;
  final String? selfieBase64;

  /// Phone screen-lock result; null when the company does not ask for it.
  final String? lockCheck;
  final String clientPunchId;

  bool get isIn => type == 'in';

  /// Body for `POST /attendance/check-in|check-out`.
  Json toBody() => {
    'clientTime': clientTime.toUtc().toIso8601String(),
    'geo': {'lat': lat, 'lng': lng, 'accuracyM': accuracyM},
    'mockLocation': mockLocation,
    'deviceId': deviceId,
    'selfieBase64': ?selfieBase64,
    'lockCheck': ?lockCheck,
    'clientPunchId': clientPunchId,
  };

  PendingPunch toPending({DateTime? now}) => PendingPunch(
    clientPunchId: clientPunchId,
    type: type,
    payload: toBody(),
    queuedAt: (now ?? DateTime.now()).toUtc(),
  );
}

sealed class PunchOutcome {
  const PunchOutcome();
}

class PunchSucceeded extends PunchOutcome {
  const PunchSucceeded(this.response);
  final PunchResponse response;
}

class PunchQueued extends PunchOutcome {
  const PunchQueued(this.punch);
  final PendingPunch punch;
}

class PunchFailed extends PunchOutcome {
  const PunchFailed(this.error);
  final ApiException error;
}

/// Sends a punch online; falls back to the offline queue when the network
/// (or the server) is unavailable. Business errors (geofence, device) are
/// returned so the UI can explain them.
class PunchService {
  PunchService({required this.api, required this.queue});

  final PunchApi api;
  final PunchQueue queue;

  Future<PunchOutcome> submit(PunchRequest request) async {
    final body = request.toBody();
    try {
      final res = request.isIn ? await api.checkIn(body) : await api.checkOut(body);
      return PunchSucceeded(res);
    } on ApiException catch (e) {
      if (e.isNetwork || (e.statusCode != null && e.statusCode! >= 500)) {
        final pending = request.toPending();
        await queue.enqueue(pending);
        return PunchQueued(pending);
      }
      return PunchFailed(e);
    }
  }
}
