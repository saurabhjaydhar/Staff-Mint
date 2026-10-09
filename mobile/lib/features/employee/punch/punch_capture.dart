import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/utils/location.dart';
import '../face/live_selfie_screen.dart';

class CapturedLocation {
  const CapturedLocation({required this.lat, required this.lng, required this.accuracyM, this.isMocked = false});
  final double lat;
  final double lng;
  final double accuracyM;
  final bool isMocked;
}

/// Device capabilities used at punch time (faked in widget tests).
abstract class PunchCapture {
  /// Throws [LocationException] when GPS is off or permission denied.
  Future<CapturedLocation> location();

  /// Front-camera selfie, ~640px JPEG, base64. Null if the user cancelled.
  /// [live] uses the blink-check camera (face check); phones that can't run
  /// it fall back to the system camera.
  Future<String?> selfie(BuildContext context, {bool live = false});

  /// Asks the phone's own screen lock (fingerprint, face, PIN or pattern).
  /// Returns `passed`, `failed` or `unavailable` (no lock set up / not
  /// supported). The biometric itself never reaches the app.
  Future<String> unlock(String reason);
}

class DevicePunchCapture implements PunchCapture {
  DevicePunchCapture({ImagePicker? picker}) : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  @override
  Future<CapturedLocation> location() async {
    final p = await LocationService.current();
    return CapturedLocation(lat: p.latitude, lng: p.longitude, accuracyM: p.accuracy, isMocked: p.isMocked);
  }

  @override
  Future<String?> selfie(BuildContext context, {bool live = false}) async {
    if (live) {
      switch (await LiveSelfieScreen.open(context)) {
        case LiveSelfieTaken(:final base64Jpeg):
          return base64Jpeg;
        case LiveSelfieCancelled():
          return null;
        case LiveSelfieUnavailable():
          break; // system camera below
      }
    }
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 640,
      maxHeight: 640,
      imageQuality: 70,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return base64Encode(bytes);
  }

  @override
  Future<String> unlock(String reason) async {
    if (kIsWeb) return LockCheck.unavailable;
    final auth = LocalAuthentication();
    try {
      if (!await auth.isDeviceSupported()) return LockCheck.unavailable;
      final ok = await auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
      return ok ? LockCheck.passed : LockCheck.failed;
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.uiUnavailable => LockCheck.unavailable,
        _ => LockCheck.failed,
      };
    } catch (_) {
      return LockCheck.unavailable;
    }
  }
}

/// Values of `lockCheck` sent with a punch.
abstract final class LockCheck {
  static const passed = 'passed';
  static const failed = 'failed';
  static const unavailable = 'unavailable';
}

final punchCaptureProvider = Provider<PunchCapture>((ref) => DevicePunchCapture());
