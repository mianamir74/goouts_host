import 'dart:io';
import 'package:image/image.dart' as img;

/// GoOuts Document Quality Inspector — v1.0
///
/// R&D Classification: Proprietary on-device ID document quality assessment.
/// Evaluates passport / driving licence captures for OCR-readiness
/// without transmitting raw document data to any third-party service.
///
/// Signals assessed:
///   - File size adequacy
///   - Image brightness (document legibility)
///   - Sharpness (text readability via Laplacian variance)
///   - Aspect ratio (document frame alignment)
///   - Edge contrast (border detection proxy for corner visibility)
class DocumentQualityInspector {
  // ── Calibrated thresholds (R&D iteration v1) ──────────────────────────────
  static const double _blurThreshold    = 80.0;   // higher bar than selfie
  static const double _minBrightness    = 50.0;
  static const double _maxBrightness    = 210.0;
  static const double _idealBrightness  = 140.0;
  static const int    _minFileSizeBytes = 60000;  // 60 KB minimum for document
  static const int    _idealFileSize    = 400000; // 400 KB ideal
  static const double _minAspectRatio   = 1.2;    // landscape document
  static const double _maxAspectRatio   = 2.2;    // widest credit-card format

  /// Inspects a document image and returns confidence scores.
  ///
  /// Returns:
  /// ```
  /// {
  ///   'isValid': bool,
  ///   'errorMessage': String?,
  ///   'scores': {
  ///     'fileQuality':    0.0–1.0,
  ///     'brightness':     0.0–1.0,
  ///     'sharpness':      0.0–1.0,
  ///     'aspectRatio':    0.0–1.0,
  ///     'edgeContrast':   0.0–1.0,
  ///     'overall':        0.0–1.0,
  ///   }
  /// }
  /// ```
  Future<Map<String, dynamic>> inspectDocument(String imagePath) async {
    final scores = <String, double>{
      'fileQuality':  0.0,
      'brightness':   0.0,
      'sharpness':    0.0,
      'aspectRatio':  0.0,
      'edgeContrast': 0.0,
      'overall':      0.0,
    };

    // ── Signal 1: File size ────────────────────────────────────────────────
    final file = File(imagePath);
    final fileSize = await file.length();
    if (fileSize < _minFileSizeBytes) {
      return {
        'isValid': false,
        'errorMessage': 'Document image too small. Ensure all text is visible and retake.',
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
        'errorMessage': 'Could not read document image. Please retake.',
        'scores': scores,
      };
    }
    final small = img.copyResize(original, width: 300);
    final grey  = img.grayscale(small);

    // ── Signal 2: Aspect ratio check ──────────────────────────────────────
    final aspectRatio = original.width / original.height;
    if (aspectRatio < _minAspectRatio || aspectRatio > _maxAspectRatio) {
      return {
        'isValid': false,
        'errorMessage': 'Document not fully visible. Place the full document within the frame.',
        'scores': scores,
      };
    }
    // Score: 1.0 at ideal card ratio (1.586), decays at extremes
    const idealRatio = 1.586;
    final ratioDiff  = (aspectRatio - idealRatio).abs();
    scores['aspectRatio'] = (1.0 - (ratioDiff / 0.6)).clamp(0.0, 1.0);

    // ── Signal 3: Brightness ───────────────────────────────────────────────
    final brightnessResult = _scoreBrightness(grey);
    if (brightnessResult['isValid'] == false) {
      return {
        'isValid': false,
        'errorMessage': brightnessResult['errorMessage'],
        'scores': scores,
      };
    }
    scores['brightness'] = brightnessResult['score'] as double;

    // ── Signal 4: Sharpness ───────────────────────────────────────────────
    final sharpnessResult = _scoreSharpness(grey);
    if (sharpnessResult['isValid'] == false) {
      return {
        'isValid': false,
        'errorMessage': sharpnessResult['errorMessage'],
        'scores': scores,
      };
    }
    scores['sharpness'] = sharpnessResult['score'] as double;

    // ── Signal 5: Edge contrast (corner/border visibility proxy) ─────────
    scores['edgeContrast'] = _scoreEdgeContrast(grey);

    // ── Weighted composite ────────────────────────────────────────────────
    // Sharpness + brightness weighted highest — text legibility critical
    scores['overall'] = (scores['fileQuality']!  * 0.15) +
                        (scores['brightness']!    * 0.25) +
                        (scores['sharpness']!     * 0.35) +
                        (scores['aspectRatio']!   * 0.15) +
                        (scores['edgeContrast']!  * 0.10);

    return {'isValid': true, 'scores': scores};
  }

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
      if (avg < _minBrightness) return {'isValid': false, 'errorMessage': 'Document too dark. Use better lighting.', 'score': 0.0};
      if (avg > _maxBrightness) return {'isValid': false, 'errorMessage': 'Too much glare on document. Adjust angle and retake.', 'score': 0.0};
      final distance = (avg - _idealBrightness).abs();
      final range    = (_maxBrightness - _minBrightness) / 2;
      return {'isValid': true, 'score': (1.0 - (distance / range)).clamp(0.0, 1.0)};
    } catch (_) {
      return {'isValid': true, 'score': 0.5};
    }
  }

  Map<String, dynamic> _scoreSharpness(img.Image grey) {
    try {
      double sumSq = 0;
      int count    = 0;
      for (int y = 1; y < grey.height - 1; y++) {
        for (int x = 1; x < grey.width - 1; x++) {
          final c   = grey.getPixel(x, y).r.toInt();
          final top = grey.getPixel(x, y - 1).r.toInt();
          final bot = grey.getPixel(x, y + 1).r.toInt();
          final lft = grey.getPixel(x - 1, y).r.toInt();
          final rgt = grey.getPixel(x + 1, y).r.toInt();
          final lap = (top + bot + lft + rgt - 4 * c).toDouble();
          sumSq += lap * lap;
          count++;
        }
      }
      final variance = count > 0 ? sumSq / count : 0.0;
      if (variance < _blurThreshold) return {'isValid': false, 'errorMessage': 'Document is blurry. Hold still and retake.', 'score': 0.0};
      return {'isValid': true, 'score': (variance / 4000.0).clamp(0.0, 1.0)};
    } catch (_) {
      return {'isValid': true, 'score': 0.5};
    }
  }

  /// Edge contrast: checks if image borders have high contrast (document corners visible)
  double _scoreEdgeContrast(img.Image grey) {
    try {
      // Sample a ring of pixels near the edges
      double edgeSum = 0;
      int    count   = 0;
      final margin   = (grey.width * 0.05).toInt();
      for (int x = margin; x < grey.width - margin; x++) {
        edgeSum += grey.getPixel(x, margin).r.toDouble();
        edgeSum += grey.getPixel(x, grey.height - margin - 1).r.toDouble();
        count += 2;
      }
      for (int y = margin; y < grey.height - margin; y++) {
        edgeSum += grey.getPixel(margin, y).r.toDouble();
        edgeSum += grey.getPixel(grey.width - margin - 1, y).r.toDouble();
        count += 2;
      }
      final edgeAvg   = edgeSum / count;
      // High contrast between edge and centre suggests document corners are visible
      double centreSum = 0;
      int    cCount    = 0;
      final cx = grey.width ~/ 2;
      final cy = grey.height ~/ 2;
      for (int y = cy - 10; y < cy + 10; y++) {
        for (int x = cx - 10; x < cx + 10; x++) {
          centreSum += grey.getPixel(x, y).r.toDouble();
          cCount++;
        }
      }
      final centreAvg = centreSum / cCount;
      final contrast  = (centreAvg - edgeAvg).abs() / 255.0;
      return contrast.clamp(0.0, 1.0);
    } catch (_) {
      return 0.5;
    }
  }
}
