import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/providers.dart';
import '../../../core/models/models.dart';
import '../../../core/utils/dates.dart';
import 'punch_queue.dart';
import 'punch_service.dart';

/// Opened in `main()` and overridden there (and in tests).
final punchQueueBoxProvider = Provider<Box<dynamic>>(
  (ref) => throw UnimplementedError('punchQueueBoxProvider not overridden'),
);

/// Small offline cache (today's attendance) — opened in `main()`.
final cacheBoxProvider = Provider<Box<dynamic>>((ref) => throw UnimplementedError('cacheBoxProvider not overridden'));

final punchQueueProvider = Provider<PunchQueue>((ref) {
  final queue = PunchQueue(HivePunchQueueStore(ref.watch(punchQueueBoxProvider)));
  ref.onDispose(queue.dispose);
  return queue;
});

final punchServiceProvider = Provider<PunchService>(
  (ref) => PunchService(api: ref.watch(attendanceApiProvider), queue: ref.watch(punchQueueProvider)),
);

/// Emits `true` whenever the device (re)gains a network connection.
final connectivityOnlineProvider = Provider<Stream<bool>>((ref) {
  try {
    return Connectivity().onConnectivityChanged
        .map((list) => list.any((c) => c != ConnectivityResult.none))
        .handleError((_) {});
  } catch (_) {
    return const Stream<bool>.empty();
  }
});

class SyncStatus {
  const SyncStatus({this.pending = 0, this.syncing = false, this.lastReport});
  final int pending;
  final bool syncing;
  final SyncReport? lastReport;

  SyncStatus copyWith({int? pending, bool? syncing, SyncReport? lastReport}) => SyncStatus(
    pending: pending ?? this.pending,
    syncing: syncing ?? this.syncing,
    lastReport: lastReport ?? this.lastReport,
  );
}

/// Keeps the offline queue flowing: syncs on start and on connectivity regain.
class PunchSyncController extends Notifier<SyncStatus> {
  StreamSubscription<int>? _queueSub;
  StreamSubscription<bool>? _netSub;

  @override
  SyncStatus build() {
    final queue = ref.watch(punchQueueProvider);
    _queueSub = queue.changes.listen((n) => state = state.copyWith(pending: n));
    _netSub = ref.watch(connectivityOnlineProvider).listen((online) {
      if (online) syncNow();
    });
    ref.onDispose(() {
      _queueSub?.cancel();
      _netSub?.cancel();
    });
    Future.microtask(syncNow);
    return SyncStatus(pending: queue.length);
  }

  Future<SyncReport> syncNow() async {
    final queue = ref.read(punchQueueProvider);
    if (queue.length == 0) return SyncReport.empty;
    state = state.copyWith(syncing: true);
    final report = await queue.sync(ref.read(attendanceApiProvider));
    if (!ref.mounted) return report;
    state = SyncStatus(pending: queue.length, syncing: false, lastReport: report);
    if (report.synced > 0) ref.invalidate(employeeTodayProvider);
    return report;
  }
}

final punchSyncProvider = NotifierProvider<PunchSyncController, SyncStatus>(PunchSyncController.new);

/// Today's info, falling back to the cached copy when offline.
class TodayState {
  const TodayState({required this.info, this.fromCache = false});
  final TodayInfo info;
  final bool fromCache;
}

final employeeTodayProvider = FutureProvider.autoDispose<TodayState>((ref) async {
  final box = ref.watch(cacheBoxProvider);
  final today = Dates.toApiDate(DateTime.now());
  try {
    final (info, json) = await ref.watch(attendanceApiProvider).today();
    await box.put('today', json);
    return TodayState(info: info);
  } on ApiException catch (e) {
    if (!e.isRetryable) rethrow;
    final cached = box.get('today');
    if (cached is Map) {
      final info = TodayInfo.fromJson(Map<String, dynamic>.from(cached));
      if (info.date == today) return TodayState(info: info, fromCache: true);
      // Keep shift/branch from the stale copy, drop the old record.
      return TodayState(
        info: TodayInfo(date: today, shift: info.shift, branch: info.branch, ownerMarks: info.ownerMarks),
        fromCache: true,
      );
    }
    return TodayState(info: TodayInfo(date: today), fromCache: true);
  }
});
