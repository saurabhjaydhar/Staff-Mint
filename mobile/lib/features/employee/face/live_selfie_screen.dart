import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/theme/app_theme.dart';
import 'liveness.dart';

/// Outcome of [LiveSelfieScreen]: a photo, a cancel, or "this phone can't
/// do it" (the caller then falls back to the system camera).
sealed class LiveSelfieResult {
  const LiveSelfieResult();
}

class LiveSelfieTaken extends LiveSelfieResult {
  const LiveSelfieTaken(this.base64Jpeg);
  final String base64Jpeg;
}

class LiveSelfieCancelled extends LiveSelfieResult {
  const LiveSelfieCancelled();
}

class LiveSelfieUnavailable extends LiveSelfieResult {
  const LiveSelfieUnavailable();
}

/// Front camera with on-device face detection (Google ML Kit): one face,
/// centred, a blink, then the photo is taken automatically. Nothing leaves
/// the phone until the photo is taken. After [manualAfter] a manual button
/// appears so nobody is ever stuck.
class LiveSelfieScreen extends StatefulWidget {
  const LiveSelfieScreen({super.key});

  static const manualAfter = Duration(seconds: 15);

  static Future<LiveSelfieResult> open(BuildContext context) async {
    if (kIsWeb) return const LiveSelfieUnavailable();
    final r = await Navigator.of(
      context,
    ).push<LiveSelfieResult>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const LiveSelfieScreen()));
    return r ?? const LiveSelfieCancelled();
  }

  @override
  State<LiveSelfieScreen> createState() => _LiveSelfieScreenState();
}

class _LiveSelfieScreenState extends State<LiveSelfieScreen> {
  final _tracker = LivenessTracker();
  final _detector = FaceDetector(
    options: FaceDetectorOptions(enableClassification: true, performanceMode: FaceDetectorMode.fast, minFaceSize: 0.2),
  );
  CameraController? _controller;
  CameraDescription? _camera;
  bool _processing = false;
  bool _capturing = false;
  bool _showManual = false;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _manualTimer;

  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  @override
  void initState() {
    super.initState();
    _start();
    _manualTimer = Timer(LiveSelfieScreen.manualAfter, () {
      if (mounted) setState(() => _showManual = true);
    });
  }

  Future<void> _start() async {
    try {
      final cams = await availableCameras();
      final front = cams.where((c) => c.lensDirection == CameraLensDirection.front).firstOrNull;
      if (front == null) return _unavailable();
      final c = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _camera = front;
      });
      await c.startImageStream(_onFrame);
    } catch (e) {
      debugPrint('Live selfie unavailable: $e');
      _unavailable();
    }
  }

  void _unavailable() {
    if (mounted) Navigator.of(context).pop(const LiveSelfieUnavailable());
  }

  Future<void> _onFrame(CameraImage image) async {
    final now = DateTime.now();
    if (_processing || _capturing || now.difference(_lastFrame) < const Duration(milliseconds: 150)) return;
    _processing = true;
    _lastFrame = now;
    try {
      final input = _toInputImage(image);
      if (input == null) return;
      final faces = await _detector.processImage(input);
      final rotated =
          input.metadata!.rotation == InputImageRotation.rotation90deg ||
          input.metadata!.rotation == InputImageRotation.rotation270deg;
      final w = rotated ? image.height : image.width;
      final h = rotated ? image.width : image.height;
      final f = faces.length == 1 ? faces.first : null;
      final sample = FaceSample(
        faces: faces.length,
        widthRatio: f == null ? null : f.boundingBox.width / w,
        centerOffset: f == null
            ? null
            : ((f.boundingBox.center.dx / w - 0.5).abs()).clamp(0, 1).toDouble() +
                  ((f.boundingBox.center.dy / h - 0.5).abs() * 0.5).clamp(0, 1).toDouble(),
        leftEyeOpen: f?.leftEyeOpenProbability,
        rightEyeOpen: f?.rightEyeOpenProbability,
      );
      final before = _tracker.hint;
      final hint = _tracker.update(sample);
      if (hint != before && mounted) setState(() {});
      if (hint == LivenessHint.done) await _capture();
    } catch (e) {
      debugPrint('Face detection failed: $e');
    } finally {
      _processing = false;
    }
  }

  InputImage? _toInputImage(CameraImage image) {
    final camera = _camera;
    final controller = _controller;
    if (camera == null || controller == null) return null;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    } else {
      final comp = _orientations[controller.value.deviceOrientation];
      if (comp == null) return null;
      rotation = InputImageRotationValue.fromRawValue((camera.sensorOrientation + comp) % 360);
    }
    if (rotation == null) return null;
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || _capturing) return;
    _capturing = true;
    if (mounted) setState(() {});
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
      final file = await c.takePicture();
      final bytes = await file.readAsBytes();
      if (mounted) Navigator.of(context).pop(LiveSelfieTaken(base64Encode(bytes)));
    } catch (e) {
      debugPrint('Capture failed: $e');
      _unavailable();
    }
  }

  @override
  void dispose() {
    _manualTimer?.cancel();
    final c = _controller;
    if (c != null) {
      if (c.value.isStreamingImages) c.stopImageStream().catchError((_) {});
      c.dispose();
    }
    _detector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final c = _controller;
    final hint = s.livenessHint(_tracker.hint.name);
    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: s.cancel,
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(const LiveSelfieCancelled()),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: ClipOval(
                      child: c == null || !c.value.isInitialized
                          ? const ColoredBox(
                              color: Colors.black26,
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: c.value.previewSize?.height ?? 480,
                                height: c.value.previewSize?.width ?? 640,
                                child: CameraPreview(c),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Column(
                children: [
                  Text(
                    hint.text,
                    key: const Key('livenessHint'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  if (hint.hint != null) Text(hint.hint!, style: const TextStyle(color: Colors.white70, fontSize: 15)),
                ],
              ),
            ),
            if (_showManual && !_capturing)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  onPressed: _capture,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: Text(s.takePhotoNow),
                ),
              )
            else
              const SizedBox(height: 64),
          ],
        ),
      ),
    );
  }
}
