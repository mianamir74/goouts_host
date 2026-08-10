import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../common/goouts_sheet.dart';
import '../short_stay/host/host_collection.dart';
import '../home/host_home_screen.dart';

class HostCreateProfileScreen extends StatefulWidget {
  const HostCreateProfileScreen({super.key});

  @override
  State<HostCreateProfileScreen> createState() => _HostCreateProfileScreenState();
}

class _HostCreateProfileScreenState extends State<HostCreateProfileScreen> {
  bool _hasPhoto = false;
  File? _profileImage;
  bool _isUploading = false;

  // KYC doc type pre-selection ('driving_licence' | 'passport' | null)
  String? _selectedDocType;

  // KYC document images
  File? _kycFrontImage;   // front of driving licence OR main passport page
  File? _kycBackImage;    // back of driving licence (not used for passport)

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) {
      // The gallery is a separate system UI. Presenting it can push this app
      // to the background, and a low memory device may unload the screen
      // behind it, so this State can be gone by the time the user has picked.
      if (!mounted) return;
      setState(() {
        _profileImage = File(picked.path);
        _hasPhoto = true;
      });
    }
  }

  Future<void> _pickKycImage(bool isFront) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked != null) {
      if (!mounted) return;   // see _pickImage above
      setState(() {
        if (isFront) {
          _kycFrontImage = File(picked.path);
        } else {
          _kycBackImage = File(picked.path);
        }
      });
    }
  }

  Future<void> _handleContinue() async {
    setState(() => _isUploading = true);
    // Tracks whether any upload failed, so the user is told instead of
    // silently continuing with nothing saved (see the catch block below).
    bool uploadFailed = false;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        // Upload profile photo
        if (_profileImage != null) {
          final ref = FirebaseStorage.instance.ref().child('stay_hosts/$uid/profile_photo.jpg');
          await ref.putFile(_profileImage!);
          final url = await ref.getDownloadURL();
          await FirebaseFirestore.instance.collection(kStayHostsCollection).doc(uid)
              .set({'photoUrl': url}, SetOptions(merge: true));
        }

        // Upload KYC documents
        final Map<String, dynamic> kycData = {};
        if (_selectedDocType != null) kycData['kycDocType'] = _selectedDocType;
        if (_kycFrontImage != null) {
          final ref = FirebaseStorage.instance.ref('stay_hosts/kyc/$uid/id_front.jpg');
          await ref.putFile(_kycFrontImage!);
          kycData['kycIdFrontUrl'] = await ref.getDownloadURL();

          // ── ⚠ NO kycStatus HERE. THE CONSUMER VERSION SETS IT. WE CANNOT. ─
          //
          // goouts_app writes kycStatus: 'pending' on this line. Copying that
          // into the host app would break the whole feature silently.
          //
          // firestore.rules guards /stay_hosts with selfEditAllowed, which
          // refuses any client write touching driverProtectedFields() —
          // kycStatus is on that list. AND THE RULE FAILS THE ENTIRE WRITE,
          // not just the offending key. So including it would deny this whole
          // set(), the documents would upload to Storage successfully, and
          // NOTHING would be recorded against the host. Uploaded, invisible.
          //
          // That is not hypothetical: it is exactly the registration-screen
          // bug from 8 August, where re-submitting sent status: 'PENDING' and
          // silently discarded every other correction the host had made.
          //
          // The host is already 'pending' from registration, and only the
          // admin panel or the server-side KYC engine may move them off it.
        }
        if (_kycBackImage != null) {
          final ref = FirebaseStorage.instance.ref('stay_hosts/kyc/$uid/id_back.jpg');
          await ref.putFile(_kycBackImage!);
          kycData['kycIdBackUrl'] = await ref.getDownloadURL();
        }
        if (kycData.isNotEmpty) {
          await FirebaseFirestore.instance.collection(kStayHostsCollection).doc(uid)
              .set(kycData, SetOptions(merge: true));
        }
      }
    } catch (_) {
      // Still non-fatal — the photo and documents can be added later from the
      // profile screen, so we don't block signup. But this used to swallow the
      // error entirely, so a failed upload looked identical to a successful
      // one: the user carried on believing their photo was saved when nothing
      // had been stored. Flag it and tell them below.
      uploadFailed = true;
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }

    if (!mounted) return;

    if (uploadFailed) {
      GoOutsSheet.warning(context,
        title: 'Photo Not Saved',
        message: 'We could not upload your photo or documents right now. '
            'You can continue and add them later from your profile.',
      );
    }

    // The consumer app pushed '/create-profile-expanded' here — a named route
    // that does not exist in this app. Left as-is it would have hit
    // onUnknownRoute and shown "Page not found" at the end of registration.
    //
    // A host has already given their business details, address and selfie by
    // this point, so there is no second form to send them to. They go to the
    // home screen, which reads /stay_hosts and tells them plainly that
    // verification is under way.
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const HostHomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0392CA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),

              // ── Header row ─────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 20),
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.pop(context),
                  ),
                  // GoOuts cloud/upload icon (top centre)
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.cloud_upload_outlined,
                        color: Colors.white, size: 20),
                  ),
                  // Spacer to balance back arrow
                  const SizedBox(width: 40),
                ],
              ),

              const SizedBox(height: 20),

              // ── Title ──────────────────────────────────────────────────
              Text(
                'Create Profile',
                style: GoogleFonts.inter(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Complete your registration to join GoOuts.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.8),
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 28),

              // ── Profile Picture ─────────────────────────────────────────
              _sectionLabel('Profile Picture'),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _pickImage,
                child: _DashedBorderContainer(
                  height: 160,
                  highlighted: _hasPhoto,
                  child: _profileImage != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(_profileImage!, fit: BoxFit.cover),
                              Container(color: Colors.black.withValues(alpha: 0.25)),
                              Center(
                                child: Text(
                                  'Tap to change',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.person_outline_rounded,
                                  color: Colors.white, size: 28),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Choose a Photo',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Make a great first impression',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.65),
                              ),
                            ),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 24),

              // ── KYC Document Selection ──────────────────────────────────
              _sectionLabel('KYC Verification (mandatory by law)'),
              const SizedBox(height: 4),
              Text(
                'Required under UK Anti-Money Laundering Regulations. Choose your ID document.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.7),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _DocTypeCard(
                      icon: Icons.credit_card_rounded,
                      label: 'Driving\nLicence',
                      selected: _selectedDocType == 'driving_licence',
                      onTap: () => setState(
                          () => _selectedDocType = 'driving_licence'),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'OR',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _DocTypeCard(
                      icon: Icons.badge_outlined,
                      label: 'Passport',
                      selected: _selectedDocType == 'passport',
                      onTap: () =>
                          setState(() => _selectedDocType = 'passport'),
                    ),
                  ),
                ],
              ),

              // ── KYC Document Upload (appears after doc type selected) ──
              if (_selectedDocType != null) ...[
                const SizedBox(height: 20),
                Text(
                  _selectedDocType == 'driving_licence'
                      ? 'Upload Driving Licence'
                      : 'Upload Passport',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _selectedDocType == 'driving_licence'
                      ? 'Upload front and back of your driving licence.'
                      : 'Upload the main photo page of your passport.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.7),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),

                // Front upload slot
                GestureDetector(
                  onTap: () => _pickKycImage(true),
                  child: _DashedBorderContainer(
                    height: 110,
                    highlighted: _kycFrontImage != null,
                    child: _kycFrontImage != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(13),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(_kycFrontImage!, fit: BoxFit.cover),
                                Container(color: Colors.black.withValues(alpha: 0.2)),
                                Align(
                                  alignment: Alignment.bottomLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0A7A3E),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text('✓ Front uploaded',
                                          style: GoogleFonts.inter(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.upload_file_rounded, color: Colors.white, size: 28),
                              const SizedBox(height: 8),
                              Text(
                                _selectedDocType == 'driving_licence' ? 'Front of Licence' : 'Main Passport Page',
                                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                              ),
                              Text('Tap to upload from gallery',
                                  style: GoogleFonts.inter(fontSize: 11, color: Colors.white.withValues(alpha: 0.65))),
                            ],
                          ),
                  ),
                ),

                // Back slot (driving licence only)
                if (_selectedDocType == 'driving_licence') ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => _pickKycImage(false),
                    child: _DashedBorderContainer(
                      height: 110,
                      highlighted: _kycBackImage != null,
                      child: _kycBackImage != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(13),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(_kycBackImage!, fit: BoxFit.cover),
                                  Container(color: Colors.black.withValues(alpha: 0.2)),
                                  Align(
                                    alignment: Alignment.bottomLeft,
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0A7A3E),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text('✓ Back uploaded',
                                            style: GoogleFonts.inter(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.upload_file_rounded, color: Colors.white, size: 28),
                                const SizedBox(height: 8),
                                Text('Back of Licence',
                                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                                Text('Tap to upload from gallery',
                                    style: GoogleFonts.inter(fontSize: 11, color: Colors.white.withValues(alpha: 0.65))),
                              ],
                            ),
                    ),
                  ),
                ],
              ],

              const SizedBox(height: 32),

              // ── Continue button ────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isUploading ? null : _handleContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _isUploading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFF0392CA)),
                          ),
                        )
                      : Text(
                          'Continue',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0392CA),
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 14),

              // ── T&C notice ─────────────────────────────────────────────
              Center(
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                    children: [
                      const TextSpan(text: 'By continuing, you agree to our '),
                      TextSpan(
                        text: 'Terms and Conditions',
                        recognizer: TapGestureRecognizer()
                          ..onTap = _showTermsSheet,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.white,
                        ),
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      );

  void _showTermsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, ctrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Terms & Conditions',
                          style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0D1B3E))),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 22),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  controller: ctrl,
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'By continuing with GoOuts, you agree to our full Terms & Conditions and Privacy Policy. KYC (identity verification) is mandatory under the UK Money Laundering, Terrorist Financing and Transfer of Funds Regulations 2017 (SI 2017/692). You can read the full terms during registration.',
                    style: GoogleFonts.inter(
                        fontSize: 13, color: Colors.grey[700], height: 1.7),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0392CA),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: Text('Close',
                        style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Dashed border container ─────────────────────────────────────────────────
class _DashedBorderContainer extends StatelessWidget {
  final Widget child;
  final double height;
  final bool highlighted;

  const _DashedBorderContainer({
    required this.child,
    required this.height,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: highlighted
            ? Colors.white
            : Colors.white.withValues(alpha: 0.45),
        radius: 14,
        dashWidth: 6,
        dashSpace: 5,
        strokeWidth: 1.5,
      ),
      child: Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: highlighted
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double dashWidth;
  final double dashSpace;
  final double strokeWidth;

  const _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.dashWidth,
    required this.dashSpace,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rect =
        Rect.fromLTWH(strokeWidth / 2, strokeWidth / 2,
            size.width - strokeWidth, size.height - strokeWidth);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final path = Path()..addRRect(rrect);

    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dashWidth),
          paint,
        );
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.dashWidth != dashWidth ||
      old.dashSpace != dashSpace ||
      old.strokeWidth != strokeWidth;
}

// ── KYC document type card ───────────────────────────────────────────────────
class _DocTypeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DocTypeCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.45),
          radius: 14,
          dashWidth: 6,
          dashSpace: 5,
          strokeWidth: 1.5,
        ),
        child: Container(
          height: 100,
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: selected ? 0.25 : 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
