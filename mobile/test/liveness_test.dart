import 'package:flutter_test/flutter_test.dart';
import 'package:staffmint/features/employee/face/liveness.dart';

FaceSample face({double l = 0.95, double r = 0.95, double width = 0.4, double off = 0.05, int faces = 1}) =>
    FaceSample(faces: faces, widthRatio: width, centerOffset: off, leftEyeOpen: l, rightEyeOpen: r);

void main() {
  test('guides the person into frame before asking for a blink', () {
    final t = LivenessTracker();
    expect(t.update(const FaceSample(faces: 0)), LivenessHint.noFace);
    expect(t.update(face(faces: 2)), LivenessHint.manyFaces);
    expect(t.update(face(width: 0.1)), LivenessHint.moveCloser);
    expect(t.update(face(off: 0.4)), LivenessHint.centerFace);
    expect(t.update(face()), LivenessHint.blink);
  });

  test('open → closed → open eyes completes it', () {
    final t = LivenessTracker();
    expect(t.update(face()), LivenessHint.blink);
    expect(t.update(face(l: 0.1, r: 0.05)), LivenessHint.blink);
    expect(t.isDone, isFalse);
    expect(t.update(face()), LivenessHint.done);
    expect(t.isDone, isTrue);
    // Stays done whatever comes next.
    expect(t.update(const FaceSample(faces: 0)), LivenessHint.done);
  });

  test('a photo held up never blinks, and losing the face restarts the blink', () {
    final t = LivenessTracker();
    for (var i = 0; i < 30; i++) {
      expect(t.update(face()), LivenessHint.blink);
    }
    t.update(face(l: 0.1, r: 0.1)); // closed
    t.update(const FaceSample(faces: 0)); // swapped out
    expect(t.update(face()), LivenessHint.blink);
    expect(t.isDone, isFalse);
  });

  test('one eye closed is not a blink', () {
    final t = LivenessTracker()..update(face());
    t.update(face(l: 0.1, r: 0.9));
    expect(t.update(face()), LivenessHint.blink);
  });

  test('phones without eye data accept a steady, centred face', () {
    final t = LivenessTracker();
    const steady = FaceSample(faces: 1, widthRatio: 0.4, centerOffset: 0.05);
    for (var i = 1; i < LivenessTracker.steadyFramesWithoutEyes; i++) {
      expect(t.update(steady), LivenessHint.holdStill);
    }
    expect(t.update(steady), LivenessHint.done);
  });
}
