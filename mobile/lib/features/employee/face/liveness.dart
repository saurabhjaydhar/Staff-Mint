/// Pure liveness logic for the live selfie: one face, close enough, centred,
/// then a blink (eyes open → closed → open). Kept free of camera / ML Kit
/// types so it can be unit-tested.
library;

/// What the camera saw in one frame.
class FaceSample {
  const FaceSample({required this.faces, this.widthRatio, this.centerOffset, this.leftEyeOpen, this.rightEyeOpen});

  /// Faces in the frame.
  final int faces;

  /// Face width ÷ frame width (upright).
  final double? widthRatio;

  /// Distance of the face centre from the frame centre, as a fraction of the frame (0 = centred).
  final double? centerOffset;

  /// ML Kit eye-open probabilities (0–1); null when the device can't classify.
  final double? leftEyeOpen;
  final double? rightEyeOpen;
}

enum LivenessHint { noFace, manyFaces, moveCloser, centerFace, blink, holdStill, done }

class LivenessTracker {
  static const minWidthRatio = 0.28;
  static const maxCenterOffset = 0.22;
  static const openAbove = 0.7;
  static const closedBelow = 0.25;

  /// Frames needed when the device cannot read the eyes (fallback: hold still).
  static const steadyFramesWithoutEyes = 8;

  bool _sawOpen = false;
  bool _sawClosed = false;
  int _steady = 0;
  LivenessHint _last = LivenessHint.noFace;

  LivenessHint get hint => _last;
  bool get isDone => _last == LivenessHint.done;

  LivenessHint update(FaceSample s) {
    if (isDone) return _last;
    return _last = _next(s);
  }

  LivenessHint _next(FaceSample s) {
    if (s.faces == 0) return _lost(LivenessHint.noFace);
    if (s.faces > 1) return _lost(LivenessHint.manyFaces);
    if ((s.widthRatio ?? 0) < minWidthRatio) return _lost(LivenessHint.moveCloser);
    if ((s.centerOffset ?? 1) > maxCenterOffset) return _lost(LivenessHint.centerFace);

    final l = s.leftEyeOpen;
    final r = s.rightEyeOpen;
    if (l == null || r == null) {
      // No eye data on this device: accept a steady, centred face.
      _steady++;
      return _steady >= steadyFramesWithoutEyes ? LivenessHint.done : LivenessHint.holdStill;
    }
    final open = l > openAbove && r > openAbove;
    final closed = l < closedBelow && r < closedBelow;
    if (!_sawOpen) {
      if (open) _sawOpen = true;
      return LivenessHint.blink;
    }
    if (!_sawClosed) {
      if (closed) _sawClosed = true;
      return LivenessHint.blink;
    }
    // Eyes open again after the blink: a live person, looking at the camera.
    return open ? LivenessHint.done : LivenessHint.blink;
  }

  /// Losing the face restarts the blink so a photo can't be swapped in mid-way.
  LivenessHint _lost(LivenessHint h) {
    _sawOpen = false;
    _sawClosed = false;
    _steady = 0;
    return h;
  }
}
