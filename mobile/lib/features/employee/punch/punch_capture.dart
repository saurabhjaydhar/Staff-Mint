import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/utils/location.dart';

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
  Future<String?> selfie();
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
  Future<String?> selfie() async {
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
}

final punchCaptureProvider = Provider<PunchCapture>((ref) => DevicePunchCapture());
