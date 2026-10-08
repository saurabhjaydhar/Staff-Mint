import 'dart:async';

import 'package:hive/hive.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/services/attendance_api.dart';
import '../../../core/utils/json.dart';

/// A punch that could not reach the server and waits in the offline queue.
class PendingPunch {
  const PendingPunch({
    required this.clientPunchId,
    required this.type,
    required this.payload,
    required this.queuedAt,
    this.attempts = 0,
    this.lastError,
  });

  final String clientPunchId;

  /// `in` or `out`.
  final String type;

  /// The original check-in/out body (clientTime, geo, deviceId, selfie…).
  final Json payload;
  final DateTime queuedAt;
  final int attempts;
  final String? lastError;

  /// Original device time of the punch (not the sync time).
  DateTime get clientTime => DateTime.tryParse(asString(payload['clientTime'])) ?? queuedAt;

  /// Body item for `POST /attendance/sync`.
  Json toSyncJson() => {...payload, 'type': type, 'clientPunchId': clientPunchId};

  PendingPunch copyWith({int? attempts, String? lastError}) => PendingPunch(
    clientPunchId: clientPunchId,
    type: type,
    payload: payload,
    queuedAt: queuedAt,
    attempts: attempts ?? this.attempts,
    lastError: lastError ?? this.lastError,
  );

  Json toJson() => {
    'clientPunchId': clientPunchId,
    'type': type,
    'payload': payload,
    'queuedAt': queuedAt.toUtc().toIso8601String(),
    'attempts': attempts,
    'lastError': lastError,
  };

  factory PendingPunch.fromJson(Json j) => PendingPunch(
    clientPunchId: asString(j['clientPunchId']),
    type: asString(j['type'], 'in'),
    payload: _deepJson(asMap(j['payload'])),
    queuedAt: asDateTimeOrNull(j['queuedAt']) ?? DateTime.now().toUtc(),
    attempts: asInt(j['attempts']),
    lastError: asStringOrNull(j['lastError']),
  );

  /// Hive returns `Map<dynamic, dynamic>` for nested maps; normalise.
  static Json _deepJson(Map<String, dynamic> m) => m.map((k, v) {
    if (v is Map) return MapEntry(k, _deepJson(asMap(v)));
    return MapEntry(k, v);
  });
}

class RejectedPunch {
  const RejectedPunch(this.punch, this.code, this.message);
  final PendingPunch punch;
  final String? code;
  final String message;
}

class SyncReport {
  const SyncReport({this.synced = 0, this.rejected = const [], this.remaining = 0, this.offline = false, this.error});

  final int synced;
  final List<RejectedPunch> rejected;
  final int remaining;

  /// True when the sync request itself failed for lack of network.
  final bool offline;
  final ApiException? error;

  static const empty = SyncReport();
}

/// Persistence for the queue. [HivePunchQueueStore] in the app.
abstract class PunchQueueStore {
  List<Json> readAll();
  Future<void> put(String key, Json value);
  Future<void> deleteAll(Iterable<String> keys);
  Future<void> clear();
}

class HivePunchQueueStore implements PunchQueueStore {
  HivePunchQueueStore(this.box);

  static const boxName = 'punch_queue';
  final Box<dynamic> box;

  @override
  List<Json> readAll() => box.values.whereType<Map>().map(asMap).toList();

  @override
  Future<void> put(String key, Json value) => box.put(key, value);

  @override
  Future<void> deleteAll(Iterable<String> keys) => box.deleteAll(keys);

  @override
  Future<void> clear() async {
    await box.clear();
  }
}

/// In-memory store (tests, previews).
class MemoryPunchQueueStore implements PunchQueueStore {
  final Map<String, Json> _items = {};

  @override
  List<Json> readAll() => _items.values.toList();

  @override
  Future<void> put(String key, Json value) async => _items[key] = value;

  @override
  Future<void> deleteAll(Iterable<String> keys) async {
    for (final k in keys) {
      _items.remove(k);
    }
  }

  @override
  Future<void> clear() async => _items.clear();
}

/// Offline punch queue: survives app restarts (Hive), idempotent by
/// `clientPunchId`, synced in order of original punch time.
class PunchQueue {
  PunchQueue(this._store);

  /// Error codes that will never succeed on retry → drop and report.
  static const permanentErrorCodes = {
    ApiErrorCode.validation,
    ApiErrorCode.outsideGeofence,
    ApiErrorCode.deviceNotBound,
    ApiErrorCode.forbidden,
    ApiErrorCode.notFound,
    ApiErrorCode.companySetupRequired,
    ApiErrorCode.featureNotInPlan,
    ApiErrorCode.planLimit,
  };

  static const batchSize = 50;

  final PunchQueueStore _store;
  final _changes = StreamController<int>.broadcast();
  Future<SyncReport>? _syncing;

  /// Emits the pending count whenever the queue changes.
  Stream<int> get changes => _changes.stream;

  List<PendingPunch> get pending {
    final list = _store.readAll().map(PendingPunch.fromJson).toList()
      ..sort((a, b) => a.clientTime.compareTo(b.clientTime));
    return list;
  }

  int get length => _store.readAll().length;
  bool get isSyncing => _syncing != null;

  /// Adds (or replaces, same `clientPunchId`) a punch.
  Future<void> enqueue(PendingPunch punch) async {
    await _store.put(punch.clientPunchId, punch.toJson());
    _notify();
  }

  Future<void> clear() async {
    await _store.clear();
    _notify();
  }

  /// Sends all pending punches. Concurrent calls share one run.
  Future<SyncReport> sync(PunchSyncApi api) {
    return _syncing ??= _doSync(api).whenComplete(() => _syncing = null);
  }

  Future<SyncReport> _doSync(PunchSyncApi api) async {
    var all = pending;
    if (all.isEmpty) return SyncReport.empty;

    var synced = 0;
    final rejected = <RejectedPunch>[];

    for (var i = 0; i < all.length; i += batchSize) {
      final batch = all.sublist(i, (i + batchSize).clamp(0, all.length));
      List<PunchSyncResult> results;
      try {
        results = await api.syncPunches(batch.map((p) => p.toSyncJson()).toList());
      } on ApiException catch (e) {
        await _markAttempt(batch, e.message);
        return SyncReport(synced: synced, rejected: rejected, remaining: length, offline: e.isNetwork, error: e);
      }

      final byId = {for (final r in results) r.clientPunchId: r};
      final toDelete = <String>[];
      final retry = <PendingPunch>[];
      for (final p in batch) {
        final r = byId[p.clientPunchId];
        if (r == null) {
          retry.add(p);
        } else if (r.ok || r.errorCode == ApiErrorCode.conflict) {
          // CONFLICT = already recorded (idempotent replay) → done.
          toDelete.add(p.clientPunchId);
          synced++;
        } else if (r.errorCode != null && permanentErrorCodes.contains(r.errorCode)) {
          toDelete.add(p.clientPunchId);
          rejected.add(RejectedPunch(p, r.errorCode, r.errorMessage ?? r.errorCode!));
        } else {
          retry.add(p.copyWith(lastError: r.errorMessage ?? r.errorCode));
        }
      }
      if (toDelete.isNotEmpty) await _store.deleteAll(toDelete);
      await _markAttempt(retry, null);
    }
    _notify();
    all = pending;
    return SyncReport(synced: synced, rejected: rejected, remaining: all.length);
  }

  Future<void> _markAttempt(List<PendingPunch> punches, String? error) async {
    for (final p in punches) {
      await _store.put(p.clientPunchId, p.copyWith(attempts: p.attempts + 1, lastError: error).toJson());
    }
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(length);
  }

  Future<void> dispose() => _changes.close();
}
