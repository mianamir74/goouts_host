// On-device face checks for KYC selfies. Google ML Kit, free, no licence key.
//
// ── WHY THIS EXISTS ──────────────────────────────────────────────────────
//
// 13 August 2026. Asked to confirm the apps had face recognition, liveness,
// auto-capture, occlusion and eye-closure checks. They did not. Worse, the
// file that looked like it did — biometric_selfie_inspector.dart — carried a
// header claiming it "replaces third-party identity verification services
// (Sumsub/Onfido)". It measures three things: file size, brightness, blur.
//
// It never looked for a face. A bright, sharp photograph of a wall, a shoe or
// a magazine scored above the 0.85 auto-approve threshold and was verified
// without a human ever seeing it.
//
// This file is the fix. It answers the question the old one never asked: is
// there actually a person in this photograph, and can we see their face?
//
// ── WHY ML KIT AND NOT A PAID SDK ────────────────────────────────────────
//
// The commercial SDKs (KBY-AI, Sumsub, Onfido, Regula) licence per package
// name. GoOuts has five: com.goouts.app, com.goouts.lead, com.goouts.host,
// the delivery driver app and merchant. That is five licences, renewed, on a
// product still in testing.
//
// ML Kit gives the same underlying signals — eye-open probability, head Euler
// angles, landmark positions — free, on-device, offline, no key, no per-app
// binding, Android and iOS. What it does NOT give is face recognition
// (matching a selfie to the ID photo), passive spoof detection, and age or
// gender estimation. Those are Stage 2 and need TFLite models.
//
// ── ⚠ WHAT THIS DOES NOT DO. READ THIS BEFORE DESCRIBING IT TO ANYONE ────
//
// This is NOT liveness detection. It confirms a face is present, unobstructed,
// facing forward and with open eyes. A printed photograph held up to the
// camera, or a face on another phone's screen, WILL pass. Defeating that needs
// either an active challenge across live frames (Stage 1b — blink, turn head)
// or a passive anti-spoof model (Stage 2).
//
// It is also NOT face recognition. Nothing here checks that the person in the
// selfie is the person on the identity document.
//
// Do not let this file's existence become the next "replaces Sumsub/Onfido".
//
// ── GDPR ─────────────────────────────────────────────────────────────────
//
// Nothing biometric is stored. No template, no embedding, no landmark
// coordinates are persisted or transmitted — the detector runs on the file,
// returns numbers between 0 and 1, and the face data is discarded. Only the
// scores leave the device.
//
// That matters: a face template IS special-category data under UK GDPR
// Article 9 and would require explicit consent, a DPIA and a retention policy.
// Stage 2 stores templates and cannot ship until that work is done.
//
// ── FAILURE POLICY ───────────────────────────────────────────────────────
//
// Two different failures, deliberately handled in opposite directions:
//
//   ML Kit could not RUN      -> fail OPEN. Returns available:false and the
//                                caller scores the selfie the old way. An
//                                unsupported device must not be unable to
//                                enrol.
//   ML Kit ran and found NO   -> fail CLOSED. That is a definitive answer and
//   face, or a bad one           it is the whole point of this file.
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceCheckResult {
  const FaceCheckResult({
    this.yaw,
    this.blocking = false,
    required this.available,
    required this.isValid,
    this.errorMessage,
    this.scores = const <String, double>{},
    this.faceCount = 0,
    this.faceBox,
  });

  /// TRUE only when the photograph cannot be used AT ALL — no face in it, or
  /// more than one person. Everything else (pose, size, eyes, lighting,
  /// sharpness) is ADVICE.
  ///
  /// ── WHY, 22 August 2026 ──────────────────────────────────────────────────
  ///
  /// A well lit, centred, straight-on selfie was refused ten times running.
  /// The face filled the on-screen bracket exactly as instructed, but the size
  /// check measures the face against the WHOLE frame and the bracket is only
  /// the middle of it — so "fill the box" and "pass the check" were different
  /// things and nothing on screen said so.
  ///
  /// Industry data is unambiguous about the cost of that: people asked to
  /// retake are three times more likely to abandon, and most give up on any
  /// verification that runs past three minutes. An app that refuses a good
  /// photograph is worse than one that accepts a mediocre one, because a
  /// mediocre photograph reaches an admin who can look at it and decide.
  ///
  /// So the app now ASSISTS rather than JUDGES. The score still travels with
  /// the record and the admin still sees it — the decision simply moved to
  /// the person qualified to make it.
  final bool blocking;

  /// Head rotation left/right in degrees, or null when ML Kit did not report
  /// it. Positive is looking to the camera's right.
  ///
  /// ⚠ NULL IS NOT ZERO. Google's own documentation is explicit that the Euler
  /// angles come back null when performanceMode is fast AND landmarks and
  /// classification are both off. Our live detector enables both, so it is
  /// populated — but anything reading this must treat null as "not measured"
  /// and stop, never as "facing straight ahead". A liveness ring that treats
  /// null as 0 sits at dead centre for ever and never fills.
  final double? yaw;

  /// False when ML Kit itself could not run. The caller should ignore this
  /// result entirely rather than treat it as a failed check.
  final bool available;

  final bool isValid;
  final String? errorMessage;

  /// faceSize, pose, eyesOpen, occlusion, overall — each 0.0 to 1.0.
  final Map<String, double> scores;

  final int faceCount;

  /// Where the face is, as FRACTIONS of the frame (0..1), not pixels.
  ///
  /// Normalised on purpose. The preview widget, the camera stream and the
  /// saved photo are three different pixel sizes; a rect in any one of them is
  /// wrong in the other two. Fractions survive the trip.
  ///
  /// Null when no face was found, or when ML Kit is unavailable.
  final Rect? faceBox;

  double get overall => scores['overall'] ?? 0.0;

  /// Used when ML Kit is missing. Nothing is asserted either way.
  static const FaceCheckResult unavailable =
      FaceCheckResult(available: false, isValid: true);
}

class FaceCheckService {
  // ── Thresholds ─────────────────────────────────────────────────────────
  //
  // Set deliberately loose. This runs on a real person in real light holding
  // a phone at arm's length, and a false rejection means a driver cannot
  // enrol and contacts support. The job is to catch a photograph of a wall,
  // not to grade a passport photo.

  /// Face bounding box as a fraction of the whole image. A selfie at arm's
  /// length is typically 0.10 to 0.40. Below 0.05 it is a person in the
  /// background, not the subject.
  static const double _minFaceArea = 0.05;
  static const double _idealFaceArea = 0.22;

  /// Degrees. Yaw is left/right, pitch is up/down, roll is head tilt.
  static const double _maxYaw = 30.0;
  static const double _maxPitch = 25.0;
  static const double _maxRoll = 30.0;

  /// ML Kit returns a probability the eye is OPEN. Below this, it is shut.
  /// 0.30 not 0.50 — naturally narrow eyes score low and rejecting those
  /// would be discriminatory as well as wrong.
  static const double _minEyeOpen = 0.30;

  /// Fraction of the six core landmarks that must be found. Missing landmarks
  /// is the closest free proxy for occlusion — a hand, a scarf or a mask over
  /// part of the face stops ML Kit locating the feature underneath.
  static const double _minLandmarks = 0.60;

  /// The six that matter. Ears and cheeks are excluded: they go missing on a
  /// perfectly good three-quarter selfie and would cause false rejections.
  static const List<FaceLandmarkType> _core = <FaceLandmarkType>[
    FaceLandmarkType.leftEye,
    FaceLandmarkType.rightEye,
    FaceLandmarkType.noseBase,
    FaceLandmarkType.leftMouth,
    FaceLandmarkType.rightMouth,
    FaceLandmarkType.bottomMouth,
  ];

  /// Runs the checks.
  ///
  /// [imageWidth] and [imageHeight] must be the real pixel dimensions of the
  /// file. They are REQUIRED rather than read here on purpose — the caller
  /// (BiometricSelfieInspector) has already decoded the image, and decoding a
  /// 12-megapixel selfie a second time costs roughly 48 MB. This app has a
  /// history of out-of-memory kills on iOS; one decode, not two.
  Future<FaceCheckResult> inspectFace(
    String imagePath, {
    required int imageWidth,
    required int imageHeight,
  }) async {
    FaceDetector? detector;
    try {
      detector = FaceDetector(
        options: FaceDetectorOptions(
          // Eye-open and smiling probabilities. Without this every
          // classification value is null and the eye check silently does
          // nothing — which is exactly the sort of quiet no-op that made the
          // old inspector look like it worked.
          enableClassification: true,
          enableLandmarks: true,
          // Contours are ~130 points per face and we use none of them.
          enableContours: false,
          // Tracking is for video streams. This is one still image.
          enableTracking: false,
          minFaceSize: 0.1,
          performanceMode: FaceDetectorMode.accurate,
        ),
      );

      final List<Face> faces =
          await detector.processImage(InputImage.fromFilePath(imagePath));

      return evaluate(faces, imageWidth, imageHeight);
    } catch (e) {
      // ML Kit itself failed — Play Services missing, model not downloaded,
      // unsupported device. Fail OPEN. See the failure policy at the top.
      debugPrint('FaceCheckService: unavailable, falling back — $e');
      return FaceCheckResult.unavailable;
    } finally {
      // MUST close. The detector holds a native model; leaking one per selfie
      // is a memory leak on the platform that can least afford it.
      try {
        await detector?.close();
      } catch (_) {}
    }
  }

  /// Judges an already-detected face. Pure — no camera, no file, no I/O.
  ///
  /// ── WHY THIS IS SEPARATE ─────────────────────────────────────────────────
  ///
  /// 20 August 2026, reported as "I tried ten times and it would not take my
  /// selfie".
  ///
  /// The old flow was: take the photo, THEN judge it, then say "Please retake."
  /// The person is asked to guess, shoot, and be told no, with nothing to aim
  /// at in between.
  ///
  /// The fix is to run these same checks on the live preview and fire the
  /// shutter only once they already pass. For that to be true rather than
  /// nearly true, the live gate and the final judgement must be THE SAME CODE.
  /// Two copies of "is this a good selfie" would drift, and the drift would
  /// show up as a shutter that fires and a photo that is then rejected — worse
  /// than what it replaced, because now the app looks broken rather than fussy.
  ///
  /// So: one evaluator, two callers.
  FaceCheckResult evaluate(List<Face> faces, int imageWidth, int imageHeight) {
    try {
      // ── No face. The bug this file was written for. ────────────────────
      if (faces.isEmpty) {
        return const FaceCheckResult(
          available: true,
          isValid: false,
          // The one genuine hard stop: there is nobody in this photograph.
          blocking: true,
          errorMessage:
              "We couldn't find a face in that photo. Hold the phone at arm's "
              'length, look straight at the camera and take it again.',
          scores: <String, double>{'overall': 0.0},
        );
      }

      // ── More than one person ───────────────────────────────────────────
      //
      // Not pedantry. An identity check where two people are in frame cannot
      // say which one it verified, and it is the obvious way to hold up
      // somebody else's photograph next to your own face.
      if (faces.length > 1) {
        return FaceCheckResult(
          available: true,
          isValid: false,
          faceCount: faces.length,
          blocking: true,
          errorMessage:
              'More than one person is in the photo. Take it again with only '
              'yourself in the frame.',
          scores: const <String, double>{'overall': 0.0},
        );
      }

      final Face face = faces.first;

      // Normalised once, then handed to every result below so the live UI can
      // draw where the face actually is while the checks are still failing —
      // which is the whole point of guiding rather than judging.
      final Rect? box = (imageWidth > 0 && imageHeight > 0)
          ? Rect.fromLTWH(
              face.boundingBox.left / imageWidth,
              face.boundingBox.top / imageHeight,
              face.boundingBox.width.abs() / imageWidth,
              face.boundingBox.height.abs() / imageHeight,
            )
          : null;

      // ── Signal 1: how much of the frame the face fills ─────────────────
      final double imageArea = (imageWidth * imageHeight).toDouble();
      final double faceArea =
          face.boundingBox.width.abs() * face.boundingBox.height.abs();
      final double areaRatio =
          imageArea > 0 ? (faceArea / imageArea).clamp(0.0, 1.0) : 0.0;

      if (areaRatio < _minFaceArea) {
        return FaceCheckResult(
          available: true,
          isValid: false,
          faceCount: 1,
          faceBox: box,
          errorMessage:
              'Your face is too small in the photo. Move closer and take it '
              'again.',
          scores: <String, double>{'faceSize': areaRatio, 'overall': 0.0},
        );
      }

      // 1.0 at the ideal, falling away either side. Too close is also wrong —
      // a face cropped at the chin loses the mouth landmarks.
      final double sizeScore = areaRatio >= _idealFaceArea
          ? (1.0 - ((areaRatio - _idealFaceArea) / 0.5)).clamp(0.0, 1.0)
          : (areaRatio / _idealFaceArea).clamp(0.0, 1.0);

      // ── Signal 2: head pose ────────────────────────────────────────────
      //
      // Null on some devices and older model versions. Null means "not
      // measured", which must not read as "0 degrees, perfectly straight" —
      // so an unmeasured angle scores neutral rather than perfect.
      final double? yaw = face.headEulerAngleY;
      final double? pitch = face.headEulerAngleX;
      final double? roll = face.headEulerAngleZ;

      if (yaw != null && yaw.abs() > _maxYaw) {
        return _poseFailure(areaRatio, sizeScore, box);
      }
      if (pitch != null && pitch.abs() > _maxPitch) {
        return _poseFailure(areaRatio, sizeScore, box);
      }
      if (roll != null && roll.abs() > _maxRoll) {
        return FaceCheckResult(
          available: true,
          isValid: false,
          faceCount: 1,
          faceBox: box,
          errorMessage:
              'Your head is tilted. Hold the phone level and take it again.',
          scores: <String, double>{'faceSize': sizeScore, 'overall': 0.0},
        );
      }

      final double poseScore = _poseScore(yaw, pitch, roll);

      // ── Signal 3: eyes open ────────────────────────────────────────────
      final double? le = face.leftEyeOpenProbability;
      final double? re = face.rightEyeOpenProbability;

      double eyeScore;
      if (le == null && re == null) {
        // Not measured. Neutral, and no rejection — see the null note above.
        eyeScore = 0.6;
      } else {
        final double lowest = math.min(le ?? 1.0, re ?? 1.0);
        if (lowest < _minEyeOpen) {
          return FaceCheckResult(
            available: true,
            isValid: false,
            faceCount: 1,
          faceBox: box,
            errorMessage:
                'Your eyes look closed. Keep both eyes open and take it again.',
            scores: <String, double>{
              'faceSize': sizeScore,
              'pose': poseScore,
              'eyesOpen': lowest,
              'overall': 0.0,
            },
          );
        }
        eyeScore = lowest.clamp(0.0, 1.0);
      }

      // ── Signal 4: occlusion, approximated by landmarks ──────────────────
      //
      // ⚠ APPROXIMATION, not detection. ML Kit has no occlusion API. If a
      // hand, scarf or mask covers a feature, the landmark under it usually
      // cannot be located — so counting the ones we found is a decent proxy.
      // It catches a hand across the mouth. It will miss sunglasses that
      // ML Kit still resolves eyes through.
      int found = 0;
      for (final FaceLandmarkType t in _core) {
        if (face.landmarks[t] != null) found++;
      }
      final double landmarkScore = found / _core.length;

      if (landmarkScore < _minLandmarks) {
        return FaceCheckResult(
          available: true,
          isValid: false,
          faceCount: 1,
          faceBox: box,
          errorMessage:
              'Part of your face is covered. Remove anything over your face '
              'and take it again.',
          scores: <String, double>{
            'faceSize': sizeScore,
            'pose': poseScore,
            'eyesOpen': eyeScore,
            'occlusion': landmarkScore,
            'overall': 0.0,
          },
        );
      }

      // ── Composite ──────────────────────────────────────────────────────
      //
      // Occlusion weighted highest: a face we can only partly see is the
      // failure mode that actually matters for identity. Size lowest — it is
      // a framing preference, and anything genuinely too small was already
      // rejected above.
      final double overall = (sizeScore * 0.15) +
          (poseScore * 0.25) +
          (eyeScore * 0.25) +
          (landmarkScore * 0.35);

      return FaceCheckResult(
        available: true,
        isValid: true,
        yaw: yaw,
        faceCount: 1,
        faceBox: box,
        scores: <String, double>{
          'faceSize': double.parse(sizeScore.toStringAsFixed(4)),
          'pose': double.parse(poseScore.toStringAsFixed(4)),
          'eyesOpen': double.parse(eyeScore.toStringAsFixed(4)),
          'occlusion': double.parse(landmarkScore.toStringAsFixed(4)),
          'overall': double.parse(overall.clamp(0.0, 1.0).toStringAsFixed(4)),
        },
      );
    } catch (e) {
      debugPrint('FaceCheckService.evaluate failed — $e');
      return FaceCheckResult.unavailable;
    }
  }

  FaceCheckResult _poseFailure(
    double areaRatio,
    double sizeScore,
    Rect? box,
  ) =>
      FaceCheckResult(
        available: true,
        isValid: false,
        faceCount: 1,
        faceBox: box,
        errorMessage:
            'Please look straight at the camera and take the photo again.',
        scores: <String, double>{'faceSize': sizeScore, 'overall': 0.0},
      );

  /// 1.0 dead straight, falling to 0 at the limits. A null angle scores 0.6 —
  /// unmeasured, not perfect.
  double _poseScore(double? yaw, double? pitch, double? roll) {
    double part(double? v, double max) {
      if (v == null) return 0.6;
      return (1.0 - (v.abs() / max)).clamp(0.0, 1.0);
    }

    return ((part(yaw, _maxYaw) * 0.45) +
            (part(pitch, _maxPitch) * 0.35) +
            (part(roll, _maxRoll) * 0.20))
        .clamp(0.0, 1.0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  LiveFaceDetector — the same checks, running on the camera preview.
//
//  Written 20 August 2026 for the auto-capture selfie.
//
//  ── WHY A SEPARATE CLASS AND NOT JUST inspectFace IN A LOOP ─────────────────
//
//  inspectFace builds a FaceDetector, uses it once and closes it. That is right
//  for a single photo and ruinous at ten frames a second — each construction
//  loads a native model.
//
//  This holds ONE detector open for the life of the camera screen and closes it
//  in dispose(). It also differs from the still-photo detector in two ways, both
//  deliberate:
//
//    performanceMode.fast   accurate cannot keep up with a live stream. Fast is
//                           slightly more willing to miss a face, which costs a
//                           frame, not a decision — another is along shortly.
//                           See AutoSelfieController.checkEveryMs for how
//                           shortly, which the liveness sweep changes.
//
//    enableTracking: true   lets ML Kit follow the same face between frames
//                           instead of re-finding it, which is both cheaper and
//                           steadier.
//
//  ⚠ THE JUDGEMENT IS NOT DUPLICATED. Both paths call FaceCheckService.evaluate.
//  The only difference is how the frame arrives.
// ─────────────────────────────────────────────────────────────────────────────

class LiveFaceDetector {
  FaceDetector? _detector;
  bool _busy = false;
  bool _disposed = false;

  /// True while a frame is being processed. The caller uses this to DROP frames
  /// rather than queue them — a queue on a 30fps stream grows without bound and
  /// the guidance ends up describing where the face was two seconds ago.
  bool get isBusy => _busy;

  FaceDetector _ensure() => _detector ??= FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          enableLandmarks: true,
          enableContours: false,
          enableTracking: true,
          minFaceSize: 0.1,
          performanceMode: FaceDetectorMode.fast,
        ),
      );

  /// Judges one live frame. Returns null if a frame was already in flight.
  Future<FaceCheckResult?> check(
    InputImage image, {
    required int imageWidth,
    required int imageHeight,
  }) async {
    if (_busy || _disposed) return null;
    _busy = true;
    try {
      final List<Face> faces = await _ensure().processImage(image);
      if (_disposed) return null;
      return FaceCheckService().evaluate(faces, imageWidth, imageHeight);
    } catch (e) {
      debugPrint('LiveFaceDetector: frame failed — $e');
      return null;
    } finally {
      _busy = false;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    try {
      await _detector?.close();
    } catch (_) {}
    _detector = null;
  }
}
