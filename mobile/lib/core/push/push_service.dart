import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/services/me_api.dart';

/// Firebase Cloud Messaging wrapper. Everything here is best-effort: the
/// Firebase project is a placeholder until real config files are added, so
/// any failure simply disables push.
class PushService {
  bool _initialized = false;
  bool get available => _initialized;
  StreamSubscription<String>? _refreshSub;
  final _opened = StreamController<Map<String, dynamic>>.broadcast();

  /// Data of notifications the user tapped (carries `companyId`).
  Stream<Map<String, dynamic>> get openedMessages => _opened.stream;

  /// Call once from `main()`. Never throws.
  Future<void> init() async {
    try {
      // Bounded: push must never block app start (missing Play Services, offline, placeholder config).
      await Firebase.initializeApp().timeout(const Duration(seconds: 5));
      _initialized = true;
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _opened.add(m.data));
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      // Delivered after the session restores (the auth controller listens).
      if (initial != null) Future.delayed(const Duration(seconds: 2), () => _opened.add(initial.data));
    } catch (e) {
      debugPrint('Push disabled (Firebase init failed): $e');
      _initialized = false;
    }
  }

  /// Requests permission and registers the FCM token with the API.
  Future<void> register(MeApi api) async {
    if (!_initialized) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      final platform = Platform.isIOS ? 'ios' : 'android';
      if (token != null) await api.registerPushToken(token, platform);
      await _refreshSub?.cancel();
      _refreshSub = messaging.onTokenRefresh.listen((t) {
        api.registerPushToken(t, platform).catchError((_) {});
      });
    } catch (e) {
      debugPrint('Push registration failed: $e');
    }
  }
}

final pushServiceProvider = Provider<PushService>((ref) => PushService());
