// ─────────────────────────────────────────────────────────────────────────────
//  Bakes a photograph's EXIF orientation into its pixels.
//
//  Written 22 August 2026, reported as "in host registration selfie
//  verification when I take selfie even I am in the box the face capture tilt
//  to another side".
//
//  ── WHY A PHOTOGRAPH COMES BACK ROTATED ─────────────────────────────────────
//
//  A phone camera sensor is mounted in a fixed orientation, usually landscape.
//  When you hold the phone upright it does NOT rotate the pixels — it writes
//  them the way the sensor read them and adds an EXIF tag saying "whoever
//  displays this should turn it 90 degrees". The photo is correct and its
//  right way up is an instruction attached to it, not a property of the
//  pixels.
//
//  That works until something reads the pixels and ignores the tag. Three
//  things in this app did:
//
//    1. image_picker with maxWidth RE-ENCODES THE FILE AND DROPS THE TAG
//       WITHOUT ROTATING THE PIXELS. This is the worst of the three, because
//       it leaves an image that is sideways with nothing left to say so. ML
//       Kit then reads a face lying on its side, reports a roll angle near
//       90 degrees, and the selfie is refused with "your head is tilted"
//       while the person is sitting perfectly straight.
//
//       That is why maxWidth has been REMOVED from every picker call and the
//       downscale moved into this file, after the rotation is baked in.
//    2. package:image's decodeImage does NOT apply the tag. Every quality
//       check ran on a sideways bitmap.
//    3. The file went to Storage with the tag intact or mangled, and whether
//       the admin panel showed it upright depended on the browser.
//
//  So the host held the phone upright, saw an upright preview, and the stored
//  photograph was on its side. Nothing was broken — everyone disagreed about
//  which way was up.
//
//  ── THE FIX, AND WHY IT IS AT THE EDGE ──────────────────────────────────────
//
//  Rotate the pixels once, immediately after capture, and drop the tag. After
//  this there is no instruction left to ignore: the file is upright to
//  anything that opens it — the quality checks, ML Kit, Storage, the admin
//  panel, a browser, a downloaded copy.
//
//  Doing it anywhere later would mean each consumer handling orientation
//  separately, which is the same one-fact-many-places fault this codebase
//  keeps paying for.
//
//  ⚠ IT NEVER BLOCKS A CAPTURE. Every failure path returns the ORIGINAL file
//  path. A photograph that is possibly sideways is a far better outcome than a
//  host who cannot finish registering because re-encoding threw.
//
//  ⚠ PORT THIS. The same image_picker call exists in goouts_app and
//  driver_app, and their selfies and ID photographs have the same fault.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Quality for the re-encoded JPEG.
///
/// 90 rather than 85: this runs AFTER image_picker has already compressed
/// once, and compressing a compressed JPEG again is where a face turns mushy.
/// The file is a few kilobytes larger and the ID text stays readable.
const int _jpegQuality = 90;

/// Longest edge of the written file, in pixels.
///
/// ⚠ THE DOWNSCALE LIVES HERE, NOT IN image_picker's maxWidth. That is the
/// whole point of this function — see the header. The picker's resize is what
/// destroyed the orientation tag in the first place, so the size limit has to
/// be applied AFTER the rotation has been baked in, not before.
///
/// 1600 rather than 1200: an ID document needs readable text and this is the
/// only resize in the pipeline now.
const int _maxEdge = 1600;

/// Rewrites [path] with its EXIF rotation applied to the pixels, downscaled.
///
/// Returns the new file's path, or [path] unchanged if anything goes wrong.
/// Never throws.
Future<String> normaliseOrientation(String path) async {
  try {
    final File source = File(path);
    if (!await source.exists()) return path;

    final Uint8List bytes = await source.readAsBytes();
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) return path;

    // The whole point. bakeOrientation reads the EXIF tag, physically rotates
    // and flips the pixels to match, and clears the tag so nothing downstream
    // applies it a second time.
    final img.Image upright = img.bakeOrientation(decoded);

    // Downscaled AFTER baking, so the rotation is already in the pixels and
    // cannot be lost by the resize. Only shrinks — a small photograph is left
    // alone rather than being blown up into a blurry larger one.
    final int w = upright.width;
    final int h = upright.height;
    final img.Image sized = (w <= _maxEdge && h <= _maxEdge)
        ? upright
        : (w >= h
            ? img.copyResize(upright, width: _maxEdge)
            : img.copyResize(upright, height: _maxEdge));

    final Uint8List out = img.encodeJpg(sized, quality: _jpegQuality);

    // Written beside the original, which is already in a cache directory that
    // the system clears — no new dependency and nothing to tidy up.
    final String dir = source.parent.path;
    final String name = source.uri.pathSegments.last;
    final File target = File('$dir/upright_$name');
    await target.writeAsBytes(out, flush: true);

    return target.path;
  } catch (e) {
    // See the header: a possibly-sideways photograph beats a host who cannot
    // finish registering.
    debugPrint('normaliseOrientation: kept the original — $e');
    return path;
  }
}
