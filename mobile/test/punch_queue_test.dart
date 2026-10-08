import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:staffmint/core/api/api_exception.dart';
import 'package:staffmint/core/api/services/attendance_api.dart';
import 'package:staffmint/core/models/models.dart';
import 'package:staffmint/core/utils/json.dart';
import 'package:staffmint/features/employee/punch/punch_queue.dart';
import 'package:staffmint/features/employee/punch/punch_service.dart';

/// Fake server for `/attendance/sync`: records calls, idempotent by
/// clientPunchId, can simulate offline or per-punch errors.
class FakeSyncApi implements PunchSyncApi {
  final List<List<Json>> calls = [];
  final Set<String> stored = {};
  bool offline = false;
  Map<String, String> errors = {}; // clientPunchId -> error code
  Set<String> omit = {};

  @override
  Future<List<PunchSyncResult>> syncPunches(List<Json> punches) async {
    if (offline) throw ApiException.network();
    calls.add(punches);
    final results = <PunchSyncResult>[];
    for (final p in punches) {
      final id = p['clientPunchId'] as String;
      if (omit.contains(id)) continue;
      final code = errors[id];
      if (code != null) {
        results.add(PunchSyncResult(clientPunchId: id, ok: false, errorCode: code, errorMessage: code));
        continue;
      }
      stored.add(id); // idempotent: re-sending the same id is harmless
      results.add(PunchSyncResult(clientPunchId: id, ok: true));
    }
    return results;
  }
}

class FakePunchApi implements PunchApi {
  ApiException? error;
  int calls = 0;

  @override
  Future<PunchResponse> checkIn(Json body) => _respond(body, 'in');

  @override
  Future<PunchResponse> checkOut(Json body) => _respond(body, 'out');

  Future<PunchResponse> _respond(Json body, String type) async {
    calls++;
    if (error != null) throw error!;
    return PunchResponse(
      record: Attendance(id: 'a1', employeeId: 'e1', date: '2026-10-08'),
      punch: Punch(id: 'p1', type: type, clientTime: DateTime.parse(body['clientTime'] as String)),
    );
  }
}

PunchRequest _request(String type, DateTime at, {String? id}) => PunchRequest(
  type: type,
  clientTime: at,
  lat: 28.61,
  lng: 77.21,
  accuracyM: 15,
  mockLocation: false,
  deviceId: 'device-1',
  selfieBase64: 'aGVsbG8=',
  clientPunchId: id,
);

void main() {
  late Directory dir;
  late Box<dynamic> box;
  late PunchQueue queue;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('punch_queue_test');
    Hive.init(dir.path);
    box = await Hive.openBox<dynamic>(HivePunchQueueStore.boxName);
    queue = PunchQueue(HivePunchQueueStore(box));
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('enqueue persists the original clientTime and payload', () async {
    final at = DateTime.utc(2026, 10, 8, 3, 31, 7);
    await queue.enqueue(_request('in', at, id: 'p-1').toPending());
    final pending = queue.pending.single;
    expect(pending.clientPunchId, 'p-1');
    expect(pending.type, 'in');
    expect(pending.clientTime, at);
    expect(pending.payload['deviceId'], 'device-1');
    expect((pending.payload['geo'] as Map)['accuracyM'], 15);
  });

  test('queue survives an app restart (box closed and reopened)', () async {
    await queue.enqueue(_request('in', DateTime.utc(2026, 10, 8, 3, 30), id: 'p-1').toPending());
    await queue.enqueue(_request('out', DateTime.utc(2026, 10, 8, 13, 0), id: 'p-2').toPending());
    await box.close();

    final reopened = await Hive.openBox<dynamic>(HivePunchQueueStore.boxName);
    final restored = PunchQueue(HivePunchQueueStore(reopened));
    expect(restored.length, 2);
    expect(restored.pending.map((p) => p.clientPunchId), ['p-1', 'p-2']);
    expect((restored.pending.first.payload['geo'] as Map)['lat'], 28.61);
  });

  test('enqueue is idempotent by clientPunchId', () async {
    final p = _request('in', DateTime.utc(2026, 10, 8, 3, 30), id: 'same').toPending();
    await queue.enqueue(p);
    await queue.enqueue(p);
    expect(queue.length, 1);
  });

  test('sync sends punches in original time order with type + clientPunchId and empties the queue', () async {
    await queue.enqueue(_request('out', DateTime.utc(2026, 10, 8, 13), id: 'late').toPending());
    await queue.enqueue(_request('in', DateTime.utc(2026, 10, 8, 3), id: 'early').toPending());
    final api = FakeSyncApi();

    final report = await queue.sync(api);

    expect(report.synced, 2);
    expect(report.remaining, 0);
    expect(queue.length, 0);
    final sent = api.calls.single;
    expect(sent.map((p) => p['clientPunchId']), ['early', 'late']);
    expect(sent.first['type'], 'in');
    expect(sent.first['clientTime'], '2026-10-08T03:00:00.000Z');
    expect(sent.first['selfieBase64'], 'aGVsbG8=');
  });

  test('offline sync keeps everything and reports offline', () async {
    await queue.enqueue(_request('in', DateTime.utc(2026, 10, 8, 3), id: 'p-1').toPending());
    final api = FakeSyncApi()..offline = true;

    final report = await queue.sync(api);

    expect(report.offline, isTrue);
    expect(report.synced, 0);
    expect(queue.length, 1);
    expect(queue.pending.single.attempts, 1);

    api.offline = false;
    final second = await queue.sync(api);
    expect(second.synced, 1);
    expect(queue.length, 0);
  });

  test('re-syncing an already stored punch is safe (idempotent replay)', () async {
    final p = _request('in', DateTime.utc(2026, 10, 8, 3), id: 'dup').toPending();
    final api = FakeSyncApi();
    await queue.enqueue(p);
    await queue.sync(api);
    await queue.enqueue(p); // e.g. app crashed before the delete was persisted
    final report = await queue.sync(api);
    expect(report.synced, 1);
    expect(api.stored, {'dup'});
    expect(queue.length, 0);
  });

  test('CONFLICT counts as already synced', () async {
    await queue.enqueue(_request('in', DateTime.utc(2026, 10, 8, 3), id: 'c').toPending());
    final api = FakeSyncApi()..errors = {'c': ApiErrorCode.conflict};
    final report = await queue.sync(api);
    expect(report.synced, 1);
    expect(queue.length, 0);
  });

  test('permanent errors are dropped and reported; retryable ones stay', () async {
    await queue.enqueue(_request('in', DateTime.utc(2026, 10, 8, 3), id: 'far').toPending());
    await queue.enqueue(_request('in', DateTime.utc(2026, 10, 8, 4), id: 'busy').toPending());
    await queue.enqueue(_request('out', DateTime.utc(2026, 10, 8, 5), id: 'missing').toPending());
    final api = FakeSyncApi()
      ..errors = {'far': ApiErrorCode.outsideGeofence, 'busy': ApiErrorCode.internal}
      ..omit = {'missing'};

    final report = await queue.sync(api);

    expect(report.synced, 0);
    expect(report.rejected.single.punch.clientPunchId, 'far');
    expect(report.rejected.single.code, ApiErrorCode.outsideGeofence);
    expect(queue.pending.map((p) => p.clientPunchId), ['busy', 'missing']);
    expect(queue.pending.first.attempts, 1);
  });

  test('concurrent sync calls share one request', () async {
    await queue.enqueue(_request('in', DateTime.utc(2026, 10, 8, 3), id: 'p').toPending());
    final api = FakeSyncApi();
    final reports = await Future.wait([queue.sync(api), queue.sync(api)]);
    expect(api.calls, hasLength(1));
    expect(identical(reports[0], reports[1]), isTrue);
  });

  test('changes stream emits the pending count', () async {
    final counts = <int>[];
    final sub = queue.changes.listen(counts.add);
    await queue.enqueue(_request('in', DateTime.utc(2026, 10, 8, 3), id: 'a').toPending());
    await queue.sync(FakeSyncApi());
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(counts, [1, 0]);
  });

  group('PunchService', () {
    test('online success does not touch the queue', () async {
      final api = FakePunchApi();
      final service = PunchService(api: api, queue: queue);
      final out = await service.submit(_request('in', DateTime.utc(2026, 10, 8, 3)));
      expect(out, isA<PunchSucceeded>());
      expect(queue.length, 0);
    });

    test('network failure enqueues with the original time', () async {
      final api = FakePunchApi()..error = ApiException.network();
      final service = PunchService(api: api, queue: queue);
      final at = DateTime.utc(2026, 10, 8, 3, 29);
      final out = await service.submit(_request('in', at, id: 'off-1'));
      expect(out, isA<PunchQueued>());
      expect(queue.pending.single.clientPunchId, 'off-1');
      expect(queue.pending.single.clientTime, at);
    });

    test('server 5xx also queues; business errors do not', () async {
      final api = FakePunchApi()
        ..error = const ApiException(code: ApiErrorCode.internal, message: 'boom', statusCode: 503);
      final service = PunchService(api: api, queue: queue);
      expect(await service.submit(_request('in', DateTime.utc(2026, 10, 8, 3))), isA<PunchQueued>());

      api.error = const ApiException(code: ApiErrorCode.outsideGeofence, message: 'far', statusCode: 422);
      final out = await service.submit(_request('in', DateTime.utc(2026, 10, 8, 4)));
      expect(out, isA<PunchFailed>());
      expect((out as PunchFailed).error.isOutsideGeofence, isTrue);
      expect(queue.length, 1);
    });
  });
}
