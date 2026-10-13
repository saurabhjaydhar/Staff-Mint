import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../core/api/providers.dart';
import '../../core/models/models.dart';
import '../../core/utils/location.dart';
import '../employee/punch/punch_providers.dart';
import 'tracking_engine.dart';

/// Opened in `main()` and overridden there.
final trackBoxProvider = Provider<Box<dynamic>>((ref) => throw UnimplementedError('trackBoxProvider not overridden'));
final locationSourceProvider = Provider<LocationSource>((ref) => GeolocatorSource());
final pointBufferProvider = Provider<PointBuffer>((ref) {
  try {
    return HivePointBuffer(ref.watch(trackBoxProvider));
  } catch (_) {
    // Tests and previews without the Hive box.
    return MemoryPointBuffer();
  }
});

final trackingEngineProvider = Provider<TrackingEngine>((ref) {
  final engine = TrackingEngine(
    api: ref.watch(trackingApiProvider),
    source: ref.watch(locationSourceProvider),
    buffer: ref.watch(pointBufferProvider),
    punchesPending: () => ref.read(punchQueueProvider).length > 0,
  );
  ref.onDispose(engine.dispose);
  return engine;
});

class TrackingState {
  const TrackingState({this.me, this.running = false});
  final MyTracking? me;
  final bool running;
}

/// Staff: starts sharing after check-in (when the owner asked and they agreed) and stops at check-out.
class TrackingController extends Notifier<TrackingState> {
  StreamSubscription<bool>? _sub;

  @override
  TrackingState build() {
    final engine = ref.watch(trackingEngineProvider);
    _sub = engine.changes.listen((on) => state = TrackingState(me: state.me, running: on));
    ref.onDispose(() => _sub?.cancel());
    return TrackingState(running: engine.running);
  }

  /// Ask the server whether to share now, and start or stop. [title]/[text]: the Android notification.
  Future<void> refresh({required String title, required String text}) async {
    final engine = ref.read(trackingEngineProvider);
    MyTracking me;
    try {
      me = await ref.read(trackingApiProvider).me();
    } catch (_) {
      // Offline: keep doing what we were doing; points wait on the phone.
      return;
    }
    state = TrackingState(me: me, running: engine.running);
    if (me.shouldShare && !engine.running) {
      try {
        await LocationService.ensurePermission();
      } catch (_) {
        return;
      }
      await engine.start(me, title: title, text: text);
    } else if (!me.shouldShare && engine.running) {
      await engine.stop();
    }
    state = TrackingState(me: me, running: engine.running);
  }

  Future<void> consent({required String title, required String text}) async {
    final me = await ref.read(trackingApiProvider).consent();
    state = TrackingState(me: me, running: state.running);
    await refresh(title: title, text: text);
  }

  Future<void> withdraw() async {
    await ref.read(trackingEngineProvider).stop(flushFirst: false);
    await ref.read(pointBufferProvider).clear();
    final me = await ref.read(trackingApiProvider).withdraw();
    state = TrackingState(me: me, running: false);
  }

  /// Checked out: send what's left; the server then says stop.
  Future<void> checkedOut() async {
    final engine = ref.read(trackingEngineProvider);
    if (engine.running) await engine.stop();
  }
}

final trackingControllerProvider = NotifierProvider<TrackingController, TrackingState>(TrackingController.new);
