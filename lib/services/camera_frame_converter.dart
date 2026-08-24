// ─────────────────────────────────────────────────────────────────────────────
//  CameraImage -> InputImage, for live ML Kit detection.
//
//  Written 20 August 2026 for the auto-capture selfie.
//
//  ── WHY THIS IS FIDDLY AND WHY IT IS ITS OWN FILE ───────────────────────────
//
//  ML Kit will not take a Flutter CameraImage. It wants bytes plus a format
//  plus a ROTATION, and every one of those differs by platform:
//
//    Android   YUV_420_888 in three planes. ML Kit wants NV21, so the planes
//              have to be concatenated. Rotation is the sensor orientation
//              combined with how the phone is being held.
//
//    iOS       BGRA8888 in one plane, and the rotation is already applied.
//
//  Get the rotation wrong and nothing breaks — that is the trap. ML Kit simply
//  finds no face, or finds one lying on its side and reports a 90 degree roll.
//  The screen then says "your head is tilted" to somebody sitting perfectly
//  straight, for ever. There is no error to read and nothing to search for.
//
//  Kept separate from the widget so it can be reasoned about on its own, and so
//  the next camera feature does not reinvent it slightly differently.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class CameraFrameConverter {
  const CameraFrameConverter._();

  static const Map<int, InputImageRotation> _rotations =
      <int, InputImageRotation>{
    0: InputImageRotation.rotation0deg,
    90: InputImageRotation.rotation90deg,
    180: InputImageRotation.rotation180deg,
    270: InputImageRotation.rotation270deg,
  };

  /// Returns null when the frame cannot be represented — an unexpected format,
  /// or a rotation we cannot resolve.
  ///
  /// Null means SKIP THIS FRAME, never "no face". The caller must not treat a
  /// conversion failure as a failed check, or an unsupported device would show
  /// "we can't find your face" and never recover.
  static InputImage? toInputImage(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) {
    final InputImageRotation? rotation =
        _rotationFor(camera, deviceOrientation);
    if (rotation == null) return null;

    // ⚠ NO ENUM SNIFFING. An earlier version compared image.format against
    // several InputImageFormat members to decide whether the frame was usable.
    // Those member names vary between plugin versions, and naming one that does
    // not exist is a compile error found by a build rather than by reading —
    // the same trap as an icon that turned out not to ship in this Flutter
    // version.
    //
    // Only two format names are needed here, both of which are what Google's
    // own documentation requires: nv21 on Android, bgra8888 on iOS. Whether a
    // frame can be converted is decided by its PLANES, which is a property of
    // the data rather than of a plugin's vocabulary.
    if (Platform.isAndroid) {
      final Uint8List? bytes = _nv21(image);
      if (bytes == null) return null;
      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    }

    // iOS: one BGRA plane, already the right way up.
    if (image.planes.length != 1) return null;
    return InputImage.fromBytes(
      bytes: image.planes.first.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.bgra8888,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  /// Sensor orientation combined with how the phone is being held.
  ///
  /// Front cameras are mirrored, so the two rotations ADD instead of
  /// subtracting. Getting this backwards is the silent 90-degree bug described
  /// at the top of the file.
  static InputImageRotation? _rotationFor(
    CameraDescription camera,
    DeviceOrientation orientation,
  ) {
    if (Platform.isIOS) {
      return _rotations[camera.sensorOrientation];
    }
    const Map<DeviceOrientation, int> deviceDegrees =
        <DeviceOrientation, int>{
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    final int? d = deviceDegrees[orientation];
    if (d == null) return null;

    final int degrees = camera.lensDirection == CameraLensDirection.front
        ? (camera.sensorOrientation + d) % 360
        : (camera.sensorOrientation - d + 360) % 360;
    return _rotations[degrees];
  }

  /// Concatenates the three YUV planes into NV21.
  ///
  /// NV21 is Y in full, then V and U INTERLEAVED — V first. Writing U first
  /// produces a picture with the colours swapped, which a human would spot
  /// instantly and a face detector very often would not: it still finds a face,
  /// and every check quietly runs against slightly wrong data.
  static Uint8List? _nv21(CameraImage image) {
    try {
      if (image.planes.length < 3) {
        // Already NV21 or a single interleaved plane — hand it over as is.
        return image.planes.first.bytes;
      }
      final int width = image.width;
      final int height = image.height;
      final Plane y = image.planes[0];
      final Plane u = image.planes[1];
      final Plane v = image.planes[2];

      final Uint8List out = Uint8List(width * height + (width * height ~/ 2));
      int o = 0;

      for (int row = 0; row < height; row++) {
        final int start = row * y.bytesPerRow;
        out.setRange(o, o + width, y.bytes, start);
        o += width;
      }

      final int uvRowStride = u.bytesPerRow;
      final int uvPixelStride = u.bytesPerPixel ?? 1;
      for (int row = 0; row < height ~/ 2; row++) {
        for (int col = 0; col < width ~/ 2; col++) {
          final int i = row * uvRowStride + col * uvPixelStride;
          if (i >= v.bytes.length || i >= u.bytes.length) return null;
          out[o++] = v.bytes[i];
          out[o++] = u.bytes[i];
        }
      }
      return out;
    } catch (e) {
      debugPrint('CameraFrameConverter: NV21 conversion failed — $e');
      return null;
    }
  }
}
