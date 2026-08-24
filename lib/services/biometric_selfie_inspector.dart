import 'dart:io';
import 'package:image/image.dart' as img;

import 'face_check_service.dart';

/// GoOuts Selfie Inspector — v3.0
///
/// On-device selfie assessment. Two layers:
///
///   IMAGE QUALITY  file size, brightness, sharpness. Is the photograph
///                  technically usable?
///   FACE           is there one person in it, facing the camera, eyes open,
///                  face unobstructed? Google ML Kit, on-device, free.
///
/// Emits confidence scores 0.0–1.0 which the caller passes to the server-side
/// KYC Auto-Decision Engine (kycAutoDecision).
///
/// ── ⚠ WHAT CHANGED IN v3, AND WHY IT MATTERS ────────────────────────────
///
/// v2 carried this header: "Replaces third-party identity verification
/// services (Sumsub/Onfido) with a zero-cost, zero-latency, privacy-
/// preserving local analysis engine."
///
/// That was not true and it was dangerous, because it was believed. v2
/// imported one package — image — and measured file size, brightness and blur.
/// It never looked for a face. A bright, sharp photograph of a wall, a shoe or
/// a magazine scored above the 0.85 auto-approve threshold and was verified
/// without a human ever seeing it.
///
/// v3 adds the face layer. It still does NOT replace Sumsub or Onfido:
///
///   NO liveness      a printed photo or a face on another screen passes
///   NO recognition   nothing checks the selfie is the person on the ID
///   NO age or gender estimation
///
/// Those are Stage 2 and need TFLite models. Please do not restore a sentence
/// to this header that claims otherwise.
///
/// Nothing biometric is stored. The detector returns numbers; the face data is
/// discarded. See face_check_service.dart for the GDPR note.
class BiometricSelfieInspector {
  // ── Calibrated thresholds (R&D iteration v2) ──────────────────────────────
  static const double _blurThreshold    = 60.0;
  static const double _minBrightness    = 40.0;
  static const double _maxBrightness    = 220.0;
  static const double _idealBrightness  = 130.0; // photometric ideal
  static const int    _minFileSizeBytes = 40000;  // 40 KB minimum

  /// File size at which fileQuality reaches 1.0.
  ///
  /// ── ⚠ RECALIBRATED 24 August 2026. 250 KB WAS MEASURED ON A DIFFERENT
  ///    PIPELINE AND SILENTLY BECAME UNREACHABLE. ─────────────────────────────
  ///
  /// fileQuality is fileSize / this, clamped. 250 KB was chosen when the file
  /// reaching here was the camera's own output — an iPhone selfie of 1.5 to 3
  /// MB, which clamps to 1.0 without trying.
  ///
  /// normaliseOrientation now sits in front of this: it re-encodes at quality
  /// 90 and caps the longest edge at 1600px, so the same selfie arrives at
  /// roughly 150–250 KB. Against a 250 KB ideal that is a fileQuality of 0.6 to
  /// 1.0 instead of a certain 1.0 — a real drop in the auto-approval score,
  /// caused by a change that had nothing to do with quality and everything to
  /// do with rotation.
  ///
  /// ⚠ THE FLOOR ABOVE IS THE ACTUAL PROTECTION. _minFileSizeBytes rejects
  /// genuine rubbish outright. This constant only decides where a good file
  /// stops earning more credit for being bigger, and a well compressed sharp
  /// image is not worse than a bloated one — sharpness is measured directly,
  /// on its own, at more than twice this weight.
  static const int    _idealFileSize    = 120000; // 120 KB, post-normalisation

  /// Inspects selfie and returns confidence scores for each signal.
  ///
  /// Returns:
  /// ```
  /// {
  ///   'isValid': bool,
  ///   'errorMessage': String?,   // only if isValid == false
  ///   'scores': {
  ///     'fileQuality':  0.0–1.0,  // file size signal
  ///     'brightness':   0.0–1.0,  // lighting quality
  ///     'sharpness':    0.0–1.0,  // focus / blur detection
  ///     'overall':      0.0–1.0,  // weighted composite
  ///   }
  /// }
  /// ```
  Future<Map<String, dynamic>> inspectSelfie(String imagePath) async {
    final scores = <String, double>{
      'fileQuality': 0.0,
      'brightness':  0.0,
      'sharpness':   0.0,
      'overall':     0.0,
    };

    // ── Signal 1: File size quality ────────────────────────────────────────
    final file = File(imagePath);
    final fileSize = await file.length();

    if (fileSize < _minFileSizeBytes) {
      return {
        'isValid': false,
        'errorMessage': 'Image too dark or low quality. Ensure good lighting and retake.',
        'scores': scores,
      };
    }

    scores['fileQuality'] = (fileSize / _idealFileSize).clamp(0.0, 1.0);

    // ── Decode + downsample ────────────────────────────────────────────────
    final bytes = await file.readAsBytes();
    final original = img.decodeImage(bytes);
    if (original == null) {
      return {
        'isValid': false,
        // Nothing decodable here at all. Genuinely unusable.
        'blocking': true,
        'errorMessage': 'Could not read selfie. Please retake.',
        'scores': scores,
      };
    }
    final small = img.copyResize(original, width: 200);
    final grey  = img.grayscale(small);

    // ── Signal 2: Brightness score ─────────────────────────────────────────
    final brightnessResult = _scoreBrightness(grey);
    if (brightnessResult['isValid'] == false) {
      return {
        'isValid': false,
        'errorMessage': brightnessResult['errorMessage'],
        'scores': scores,
      };
    }
    scores['brightness'] = brightnessResult['score'] as double;

    // ── Signal 3: Sharpness score (Laplacian variance) ────────────────────
    final sharpnessResult = _scoreSharpness(grey);
    if (sharpnessResult['isValid'] == false) {
      return {
        'isValid': false,
        'errorMessage': sharpnessResult['errorMessage'],
        'scores': scores,
      };
    }
    scores['sharpness'] = sharpnessResult['score'] as double;

    // ── Signal 4: FACE ─────────────────────────────────────────────────────
    //
    // Runs last, and only once the image is known to be technically usable.
    // ML Kit on a photograph already established as pitch black or badly out
    // of focus tells you nothing you did not know, and costs a model load.
    //
    // Dimensions come from the decode above rather than being read again
    // inside the service — a second decode of a 12-megapixel selfie is about
    // 48 MB, and this app has a history of out-of-memory kills on iOS.
    final FaceCheckResult faceResult = await FaceCheckService().inspectFace(
      imagePath,
      imageWidth: original.width,
      imageHeight: original.height,
    );

    if (faceResult.available) {
      scores['face'] = faceResult.overall;
      scores['faceSize'] = faceResult.scores['faceSize'] ?? 0.0;
      scores['facePose'] = faceResult.scores['pose'] ?? 0.0;
      scores['eyesOpen'] = faceResult.scores['eyesOpen'] ?? 0.0;
      scores['faceOcclusion'] = faceResult.scores['occlusion'] ?? 0.0;

      // A face failure is a HARD stop. Unlike the quality gates above, "there
      // is no face here" is not a lighting problem the applicant can be scored
      // down for — it means this is not a selfie.
      if (!faceResult.isValid) {
        scores['overall'] = 0.0;
        return {
          'isValid': false,
          // ⚠ ONLY "no face" AND "more than one face" STOP THE FLOW.
          // Pose, size, eyes and occlusion are advice — see the note on
          // FaceCheckResult.blocking. A good selfie was being refused ten
          // times in a row because the size check and the on-screen bracket
          // measured different things.
          'blocking': faceResult.blocking,
          'errorMessage': faceResult.errorMessage ??
              'We could not verify your face in that photo. Please retake it.',
          'scores': scores,
        };
      }
    }

    // ── Weighted composite score ───────────────────────────────────────────
    //
    // The face carries 45% when it was measured. That is deliberate: the
    // technical signals answer "is this a good photograph", and only the face
    // signal answers "is this a photograph of the applicant". A very sharp,
    // well-lit picture of a wall now tops out at 0.55 and lands in manual
    // review instead of being auto-approved at 0.85.
    //
    // When ML Kit could not run at all — Play Services missing, model not
    // downloaded, unsupported device — we fall back to the v2 weights rather
    // than punishing the applicant for their handset. See the failure policy
    // in face_check_service.dart.
    if (faceResult.available) {
      scores['overall'] = (scores['fileQuality']! * 0.10) +
                          (scores['brightness']!  * 0.20) +
                          (scores['sharpness']!   * 0.25) +
                          (scores['face']!        * 0.45);
    } else {
      scores['overall'] = (scores['fileQuality']! * 0.20) +
                          (scores['brightness']!  * 0.35) +
                          (scores['sharpness']!   * 0.45);
    }

    return {
      'isValid': true,
      'faceChecked': faceResult.available,
      'scores': scores,
    };
  }

  // ── Brightness scoring ────────────────────────────────────────────────────
  Map<String, dynamic> _scoreBrightness(img.Image grey) {
    try {
      double total = 0;
      final count = grey.width * grey.height;
      for (int y = 0; y < grey.height; y++) {
        for (int x = 0; x < grey.width; x++) {
          total += grey.getPixel(x, y).r.toDouble();
        }
      }
      final avg = total / count;

      if (avg < _minBrightness) {
        return {'isValid': false, 'errorMessage': 'Too dark. Move to a brighter area and retake.', 'score': 0.0};
      }
      if (avg > _maxBrightness) {
        return {'isValid': false, 'errorMessage': 'Too bright. Avoid direct light behind you and retake.', 'score': 0.0};
      }

      // Score: 1.0 at ideal brightness, decays toward 0 at min/max limits
      final distance = (avg - _idealBrightness).abs();
      final range    = (_maxBrightness - _minBrightness) / 2;
      final score    = (1.0 - (distance / range)).clamp(0.0, 1.0);

      return {'isValid': true, 'score': score};
    } catch (_) {
      return {'isValid': true, 'score': 0.5};
    }
  }

  // ── Sharpness scoring (Laplacian variance method) ─────────────────────────
  Map<String, dynamic> _scoreSharpness(img.Image grey) {
    try {
      final w = grey.width;
      final h = grey.height;
      double sumSq = 0;
      int count = 0;

      for (int y = 1; y < h - 1; y++) {
        for (int x = 1; x < w - 1; x++) {
          final center = grey.getPixel(x, y).r.toInt();
          final top    = grey.getPixel(x, y - 1).r.toInt();
          final bottom = grey.getPixel(x, y + 1).r.toInt();
          final left   = grey.getPixel(x - 1, y).r.toInt();
          final right  = grey.getPixel(x + 1, y).r.toInt();
          final lap    = (top + bottom + left + right - 4 * center).toDouble();
          sumSq += lap * lap;
          count++;
        }
      }

      final variance = count > 0 ? sumSq / count : 0.0;

      if (variance < _blurThreshold) {
        return {'isValid': false, 'errorMessage': 'Selfie is blurry. Hold still and retake.', 'score': 0.0};
      }

      // Score: normalised against practical ceiling of 3000 (sharp portrait)
      final score = (variance / 3000.0).clamp(0.0, 1.0);
      return {'isValid': true, 'score': score};
    } catch (_) {
      return {'isValid': true, 'score': 0.5};
    }
  }

  void dispose() {}
}
