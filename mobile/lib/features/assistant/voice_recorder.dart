import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceClip {
  const VoiceClip({required this.base64, required this.mime, required this.duration});
  final String base64;
  final String mime;
  final Duration duration;
}

/// Hold-to-talk recorder shared by the shell's centre mic and the Mint chat.
///
/// Call [press] when the finger goes down and [release] when it lifts.
/// [release] returns the clip, or null when it was too short, cancelled or
/// the microphone is not allowed.
class VoiceRecorder {
  AudioRecorder? _recorder;
  bool _pressing = false;
  bool _recording = false;
  String? _path;
  DateTime? _startedAt;

  bool get isRecording => _recording;

  /// Starts recording. Returns false when microphone permission is missing.
  Future<bool> press() async {
    _pressing = true;
    try {
      _recorder ??= AudioRecorder();
      if (!await _recorder!.hasPermission()) return false;
      final dir = await getTemporaryDirectory();
      _path = '${dir.path}/mint_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder!.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 16000, numChannels: 1),
        path: _path!,
      );
      if (!_pressing) {
        // Finger lifted while we were starting (e.g. permission prompt).
        await _recorder!.cancel();
        return true;
      }
      _recording = true;
      _startedAt = DateTime.now();
      HapticFeedback.selectionClick().ignore();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<VoiceClip?> release({bool cancel = false}) async {
    _pressing = false;
    if (!_recording) return null;
    _recording = false;
    final duration = DateTime.now().difference(_startedAt ?? DateTime.now());
    final path = await _recorder?.stop() ?? _path;
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    await file.delete().catchError((_) => file);
    if (cancel || bytes.length < 2000) return null; // too short — accidental tap
    return VoiceClip(base64: base64Encode(bytes), mime: 'audio/mp4', duration: duration);
  }

  void dispose() => _recorder?.dispose();
}
