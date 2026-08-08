// Step 5: photographs.
//
// WIRED 8 August 2026. The Stitch version showed a dashed "Add photos" box
// with an empty handler and three stock thumbnails that were part of the
// design, not the host's property.
//
// ── UPLOADS HAPPEN HERE, NOT AT SUBMIT ─────────────────────────────────────
//
// Each photograph goes to Storage as soon as it is chosen, and only the
// resulting download URL is carried in ListingDraft. The alternative — hold
// the image bytes and upload them all on the last step — means six or eight
// full-size photographs sitting in memory across three more screens, on an
// app iOS has already killed for memory once. It also means one failed upload
// at the very end loses the lot.
//
// ⚠ PATH IS KEYED BY HOST, NOT BY LISTING, AND IT HAS TO BE. The listing does
// not exist yet — createStayListing runs on step 7. The host's uid is the only
// identifier available at upload time. storage.rules matches this exactly:
// stay_listings/{hostUid}/{fileName}, owner-writes, public-read.
//
// Public read is deliberate: a guest browses live listings before signing in,
// and firestore.rules already allows that. Requiring auth on the image would
// show broken thumbnails to precisely the people we want to convert.
//
// ── PHOTOS ARE NOT REQUIRED TO CONTINUE, BUT ARE WARNED ABOUT ──────────────
//
// createStayListing accepts an empty photo list on purpose, so a host can get
// the listing saved and add pictures later. But the admin Listing Approval
// page flags "No photos" in amber and says a listing with none should not go
// live — so a host who skips this will be rejected at approval. Better they
// hear it here than a week later.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../theme/goouts_colors.dart';
import 'host_routes.dart';
import 'listing_draft.dart';
import 'wizard_shell.dart';

class PhotoUploadScreen extends StatefulWidget {
  const PhotoUploadScreen({super.key});

  @override
  State<PhotoUploadScreen> createState() => _PhotoUploadScreenState();
}

class _PhotoUploadScreenState extends State<PhotoUploadScreen> {
  final _draft = ListingDraft.instance;
  final _picker = ImagePicker();

  bool _busy = false;
  String? _error;

  /// Server caps at 30. Stopping the host here is kinder than letting them
  /// upload 40 and silently dropping ten.
  static const int _maxPhotos = 30;

  Future<void> _add({required ImageSource source}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _error = 'Your session expired. Sign out and back in.');
      return;
    }
    if (_draft.photos.length >= _maxPhotos) {
      setState(() => _error = 'That is the maximum of $_maxPhotos photos.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // Resized on the device before upload. A modern phone camera produces
      // 4-6 MB per shot; twenty of those is a slow upload on a poor
      // connection and a large bill for images that are displayed at a
      // fraction of that size.
      final XFile? picked = await _picker.pickImage(
        source: source,
        maxWidth: 2000,
        imageQuality: 82,
      );
      if (picked == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }

      final stamp = DateTime.now().millisecondsSinceEpoch;
      final name = '${stamp}_${_draft.photos.length}.jpg';
      final ref =
          FirebaseStorage.instance.ref().child('stay_listings').child(uid).child(name);

      await ref.putFile(
        File(picked.path),
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await ref.getDownloadURL();

      if (!mounted) return;
      setState(() {
        // storagePath is stored alongside the URL because a download URL
        // cannot be turned back into a file reference. Without it, deleting a
        // photograph later means orphaning the file in Storage forever.
        _draft.photos.add(<String, String>{
          'url': url,
          'storagePath': ref.fullPath,
        });
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not upload that photo. $e';
      });
    }
  }

  Future<void> _remove(int index) async {
    final photo = _draft.photos[index];
    setState(() {
      _draft.photos.removeAt(index);
      _error = null;
    });

    // Best effort. The photograph is already off the listing; failing to tidy
    // Storage must not put it back or block the host.
    final path = photo['storagePath'] ?? '';
    if (path.isEmpty) return;
    try {
      await FirebaseStorage.instance.ref(path).delete();
    } catch (_) {}
  }

  void _saveAndContinue() =>
      Navigator.of(context).pushNamed(HostRoutes.newPricing);

  @override
  Widget build(BuildContext context) {
    final count = _draft.photos.length;

    return HostWizardScaffold(
      step: 5,
      heading: 'Add some photographs',
      subheading:
          'The first photograph is the one guests see in search results. '
          'Bright, wide shots of real rooms do best.',
      canContinue: true,
      busy: _busy,
      onNext: _saveAndContinue,
      nextLabel: count == 0 ? 'Skip for now' : 'Next',
      children: <Widget>[
        if (_error != null) ...<Widget>[
          _notice(_error!, GoOutsColors.error, Icons.error_outline_rounded),
          const SizedBox(height: 14),
        ],
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    _busy ? null : () => _add(source: ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Choose photos'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 50)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    _busy ? null : () => _add(source: ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Take a photo'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 50)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (count == 0)
          _notice(
            'No photographs yet. You can add them later, but GoOuts will not '
            'approve a listing without any — so it will not reach guests '
            'until you do.',
            GoOutsColors.warning,
            Icons.image_not_supported_rounded,
          )
        else ...<Widget>[
          Text(
            '$count of $_maxPhotos',
            style: GoogleFonts.inter(
              color: GoOutsColors.onSurfaceVariant,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: count,
            itemBuilder: (context, i) => _thumb(i),
          ),
        ],
        if (_busy) ...<Widget>[
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Text('Uploading…',
                  style: GoogleFonts.inter(
                      fontSize: 13, color: GoOutsColors.body)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _thumb(int i) {
    final url = _draft.photos[i]['url'] ?? '';
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            // A thumbnail that fails to load must look like a failure, not
            // like an empty slot the host will try to fill again.
            errorBuilder: (_, _, _) => Container(
              color: GoOutsColors.background,
              child: const Icon(Icons.broken_image_outlined,
                  color: GoOutsColors.onSurfaceVariant),
            ),
          ),
        ),
        if (i == 0)
          Positioned(
            left: 4,
            bottom: 4,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: GoOutsColors.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('Cover',
                  style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ),
          ),
        Positioned(
          right: 2,
          top: 2,
          child: InkWell(
            onTap: _busy ? null : () => _remove(i),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded,
                  size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _notice(String text, Color colour, IconData icon) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colour.withValues(alpha: 0.28)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 18, color: colour),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.inter(
                    fontSize: 13, color: GoOutsColors.body, height: 1.45),
              ),
            ),
          ],
        ),
      );
}
