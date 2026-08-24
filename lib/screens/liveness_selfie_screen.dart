// ─────────────────────────────────────────────────────────────────────────────
//  The KYC selfie step: live preview, head-sweep liveness, automatic shutter.
//
//  Built 24 August 2026, porting the consumer app's flow to goouts_host,
//  driver_app and goouts_drapp.
//
//  ── WHY THIS IS A SCREEN AND NOT A PORT OF kyc_screen ───────────────────────
//
//  goouts_app does all of this inside a 2,400 line kyc_screen that also owns the
//  ID step, the review step, the submit call and the status panels. Copying that
//  into three apps whose registration flows are completely different — and which
//  currently WORK — would mean rewriting three working sign-up journeys to gain
//  one camera.
//
//  So the camera is the only thing that moved. This screen opens, does the whole
//  selfie job, and returns a LivenessSelfieResult. Each app's existing
//  "take a selfie" method calls it instead of image_picker and carries on
//  exactly as before. The registration screens did not change shape.
//
//  ── WHAT IT REPLACES, AND WHY THAT MATTERED ─────────────────────────────────
//
//  image_picker with source: camera hands the job to the phone's own camera app.
//  You get one finished photograph and no say in it — no live guidance, no way
//  to check the framing before the shutter, and no frames to measure a head
//  turning. The photo is then judged AFTER the fact, which is how a person ends
//  up being told "please retake" ten times with nothing to aim at.
//
//  ⚠ THIS FILE IS AN IDENTICAL COPY IN goouts_host, driver_app AND
//  goouts_drapp. There is no shared package between these repos — they are three
//  separate GitHub projects. If you change it here, change it in the other two.
//  The same is true of the five services it depends on.
//
//  ── THE RULE THIS SCREEN OBEYS ──────────────────────────────────────────────
//
//  IT ASSISTS. IT DOES NOT JUDGE. The liveness ring timing out does not stop
//  anybody: the photograph is still taken and the record carries
//  livenessComplete: false for the reviewer. Nothing here is a gate the person
//  can fail their way into being stuck behind.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/auto_selfie_controller.dart';
import '../services/biometric_selfie_inspector.dart';
import '../services/face_check_service.dart';
import '../services/image_orientation.dart';
import '../services/liveness_ring_controller.dart';
import '../widgets/liveness_ring.dart';

const Color _kBrand = Color(0xFF0392CA);
const Color _kGreen = Color(0xFF22C55E);

/// What the selfie step hands back to whoever opened it.
///
/// ⚠ THE SCORES AND THE LIVENESS NOTE TRAVEL WITH THE PHOTO. The registration
/// screen must write them alongside the image, because they are what the admin
/// reviewer reads to decide how hard to look. A photograph arriving with no
/// opinion attached is the blind approval the on-device checks exist to prevent.
class LivenessSelfieResult {
  const LivenessSelfieResult({
    required this.path,
    required this.livenessComplete,
    required this.livenessNote,
    required this.scores,
    this.advice,
  });

  /// Upright, downscaled, EXIF baked in. Safe for any reader.
  final String path;

  /// False means the ring did not close and the photo was taken anyway.
  /// NOT a rejection — a note for the reviewer.
  final bool livenessComplete;

  /// The sentence the person was shown when it did not close. Empty otherwise.
  final String livenessNote;

  /// Quality scores from BiometricSelfieInspector.
  final Map<String, double> scores;

  /// Set when the photo was accepted with a caveat. Null when it passed clean.
  final String? advice;
}

class LivenessSelfieScreen extends StatefulWidget {
  const LivenessSelfieScreen({super.key});

  /// Opens the step. Returns null if the person backed out without a photo.
  static Future<LivenessSelfieResult?> open(BuildContext context) {
    return Navigator.of(context).push<LivenessSelfieResult>(
      MaterialPageRoute<LivenessSelfieResult>(
        builder: (_) => const LivenessSelfieScreen(),
      ),
    );
  }

  @override
  State<LivenessSelfieScreen> createState() => _LivenessSelfieScreenState();
}

class _LivenessSelfieScreenState extends State<LivenessSelfieScreen> {
  final BiometricSelfieInspector _inspector = BiometricSelfieInspector();

  CameraController? _camera;
  AutoSelfieController? _auto;
  LivenessRingController? _ring;

  bool _ready = false;
  bool _checking = false;
  bool _introShown = false;
  String _error = '';

  bool _livenessComplete = false;
  String _livenessNote = '';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final List<CameraDescription> cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() => _error = 'No camera found on this device.');
        return;
      }
      final CameraDescription front = cams.firstWhere(
        (CameraDescription c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );

      // ── ⚠ THE IMAGE FORMAT IS NOT OPTIONAL. ───────────────────────────────
      //
      // Leave imageFormatGroup unset and the plugin picks a default that can be
      // JPEG. A JPEG group cannot be fed to ML Kit, so startImageStream yields
      // frames the converter rejects and THE LIVE CHECK NEVER SEES A FACE —
      // silently, with no error, for ever. The preview looks perfect and the
      // ring simply never fills.
      //
      // ML Kit needs the platform's raw format: NV21 on Android, BGRA on iOS.
      final CameraController ctrl = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }

      final AutoSelfieController auto = AutoSelfieController(
        controller: ctrl,
        onCaptured: _accept,
      );
      final LivenessRingController ring = LivenessRingController();

      // The sweep happens BEFORE the photograph. The ring needs the head
      // turning; the photograph needs it straight, because a reviewer compares
      // it against a passport. A frame grabbed mid-sweep is a profile shot that
      // matches nothing.
      auto.holdShutter = true;
      auto.onResult = (FaceCheckResult r) {
        ring.onFrame(
          faceFound: r.available && r.faceCount == 1,
          // ⚠ NULL STAYS NULL. `?? 0` would read as "facing dead ahead" and peg
          // the sweep at centre for ever, with no error anywhere.
          yaw: r.yaw,
        );
      };

      ring.state.addListener(() {
        final LivenessRingState s = ring.state.value;
        // The fast sample rate belongs to the sweep, not to the screen. Raising
        // it when the camera opens means eight frames a second while somebody
        // reads the instructions, heating the phone for nothing.
        if (s == LivenessRingState.sweeping) {
          auto.checkEveryMs = AutoSelfieController.sweepCheckEveryMs;
          return;
        }
        if (s == LivenessRingState.complete ||
            s == LivenessRingState.timedOut) {
          // Released on BOTH outcomes. A timeout must never trap anybody.
          auto.holdShutter = false;
          auto.checkEveryMs = AutoSelfieController.framingCheckEveryMs;
          _livenessComplete = s == LivenessRingState.complete;
          _livenessNote = ring.failureReason.value;
          if (mounted) setState(() {});
        }
      });

      _camera = ctrl;
      _auto = auto;
      _ring = ring;
      setState(() => _ready = true);

      await auto.start();

      // Shown AFTER the preview is live, so it opens over a working camera
      // rather than a black rectangle. People trust a screen that is visibly
      // ready more than one that is visibly loading.
      if (mounted && !_introShown) {
        _introShown = true;
        await _showIntro();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not open the camera. $e');
      }
    }
  }

  /// ⚠ EVERY FAILURE PATH RETURNS false, WHICH MEANS "KEEP SCANNING".
  /// Returning true on a photo we did not keep would end the step with nothing.
  Future<bool> _accept(String rawPath) async {
    if (!mounted) return false;
    setState(() => _checking = true);

    // ⚠ BEFORE ANY INSPECTOR READS THE FILE. package:image ignores the EXIF
    // orientation tag while ML Kit honours it, so without this the face box is
    // measured in portrait against a landscape frame and a perfectly good
    // selfie is reported as containing no face at all.
    final String path = await normaliseOrientation(rawPath);
    if (!mounted) return false;

    try {
      final Map<String, dynamic> result = await _inspector.inspectSelfie(path);
      if (!mounted) return false;

      // ── ⚠ ACCEPT UNLESS IT IS UNUSABLE ────────────────────────────────────
      //
      // Only 'blocking' stops it — no face in the photograph, two people in it,
      // or a file that will not decode. Everything else is ADVICE: the photo is
      // kept, the caveat travels with it, and the reviewer decides.
      //
      // ⚠ DO NOT RESTORE AN isValid GATE HERE. That is what refused ten
      // consecutive good selfies in the consumer app, because the size check
      // measures the face against the WHOLE frame while the bracket the person
      // was filling is only the middle of it.
      final bool blocking = result['blocking'] == true;
      if (result['isValid'] != true && blocking) {
        setState(() => _checking = false);
        return false;
      }

      final String? advice = result['isValid'] == true
          ? null
          : result['errorMessage'] as String?;
      final Map<String, double> scores = (result['scores'] as Map?)?.map(
            (Object? k, Object? v) =>
                MapEntry<String, double>(k.toString(), (v as num).toDouble()),
          ) ??
          const <String, double>{};

      if (!mounted) return false;
      Navigator.of(context).pop(
        LivenessSelfieResult(
          path: path,
          livenessComplete: _livenessComplete,
          livenessNote: _livenessNote,
          scores: scores,
          advice: advice,
        ),
      );
      return true;
    } catch (_) {
      if (mounted) setState(() => _checking = false);
      return false;
    }
  }

  Future<void> _manualShutter() async {
    final CameraController? ctrl = _camera;
    if (ctrl == null || !_ready || _checking) return;
    // The stream MUST stop before takePicture — several Android devices fail
    // outright if both run at once, with a native error that says nothing.
    await _auto?.stop();
    try {
      final XFile shot = await ctrl.takePicture();
      final bool kept = await _accept(shot.path);
      if (!kept && mounted) await _auto?.restart();
    } catch (_) {
      if (mounted) await _auto?.restart();
    }
  }

  /// Puts the movement check back to the start, in place.
  ///
  /// ⚠ reset() ALONE IS NOT ENOUGH. By this point the auto controller has
  /// usually finished and left itself on `captured`, where it ignores every
  /// frame. Restarting the stream without resetting that gives a live preview
  /// that reads nothing — which looks exactly like working.
  Future<void> _retry() async {
    final AutoSelfieController? auto = _auto;
    final LivenessRingController? ring = _ring;
    if (auto == null || ring == null) return;
    ring.reset();
    auto.holdShutter = true;
    auto.checkEveryMs = AutoSelfieController.framingCheckEveryMs;
    setState(() {
      _livenessComplete = false;
      _livenessNote = '';
      _checking = false;
    });
    await auto.restart();
    if (mounted) setState(() {});
  }

  Future<void> _showIntro() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (BuildContext ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'Before we start',
                    style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Three quick steps. Nothing is recorded until the photo is taken.',
              style: TextStyle(fontSize: 13.5, height: 1.5, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            _introStep(1, 'Put your face in the circle',
                'Hold the phone at arm\'s length in good light.'),
            _introStep(2, 'Press start, then turn your head',
                'Left first, then all the way to the right. The ring fills as '
                'you go.'),
            _introStep(3, 'Look straight ahead',
                'The photo is taken for you once you hold still.'),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  backgroundColor: _kBrand,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26)),
                ),
                child: const Text("I'm ready",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _introStep(int n, String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                  color: Color(0xFFE8F4FB), shape: BoxShape.circle),
              child: Text('$n',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _kBrand)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A))),
                  const SizedBox(height: 2),
                  Text(body,
                      style: const TextStyle(
                          fontSize: 12.5, height: 1.45, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      );

  @override
  void dispose() {
    // ⚠ onResult FIRST. The closure holds the ring, so a frame already in
    // flight would call into it after it had gone.
    _auto?.onResult = null;
    _auto?.dispose();
    _auto = null;
    // ⚠ AND THE RING. Forgetting this leaves six live notifiers and, mid-sweep,
    // a twenty second timer counting down against a screen that no longer
    // exists. It was missed on exactly this path in the consumer app.
    _ring?.dispose();
    _ring = null;
    _camera?.dispose();
    _camera = null;
    // BiometricSelfieInspector holds no native handle — it opens and closes a
    // detector per call — so there is deliberately nothing to release here.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        foregroundColor: const Color(0xFF0F172A),
        title: const Text('Verification Selfie',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        actions: <Widget>[
          if (_ready)
            IconButton(
              tooltip: 'Instructions',
              icon: const Icon(Icons.help_outline_rounded),
              onPressed: _showIntro,
            ),
        ],
      ),
      body: _error.isNotEmpty
          ? _errorView()
          : !_ready
              ? const Center(
                  child: CircularProgressIndicator(color: _kBrand))
              : _cameraView(),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.videocam_off_rounded,
                  color: Colors.white54, size: 56),
              const SizedBox(height: 18),
              Text(_error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 14, height: 1.5)),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(backgroundColor: _kBrand),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      );

  Widget _cameraView() {
    final AutoSelfieController auto = _auto!;
    final LivenessRingController ring = _ring!;

    return Column(
      children: <Widget>[
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              CameraPreview(_camera!),

              // ── THE RING ────────────────────────────────────────────────
              Center(
                child: ValueListenableBuilder<LivenessRingState>(
                  valueListenable: ring.state,
                  builder: (_, LivenessRingState st, Widget? child) {
                    if (st == LivenessRingState.complete ||
                        st == LivenessRingState.timedOut) {
                      return const SizedBox.shrink();
                    }
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Stack(
                          alignment: Alignment.center,
                          children: <Widget>[
                            ValueListenableBuilder<List<bool>>(
                              valueListenable: ring.lit,
                              builder: (_, List<bool> lit, Widget? child) =>
                                  LivenessRing(lit: lit),
                            ),
                            if (st == LivenessRingState.countdown)
                              ValueListenableBuilder<int>(
                                valueListenable: ring.count,
                                builder: (_, int n, Widget? child) => Text(
                                  '$n',
                                  style: const TextStyle(
                                    fontSize: 72,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),

                        // ── WHICH WAY NOW ─────────────────────────────────
                        //
                        // The ring says how much is done; these say which side
                        // still needs doing, without asking anybody to read a
                        // sentence while they are concentrating on holding a
                        // phone steady and turning their head.
                        //
                        // ⚠ FED THE SAME `lit` LIST THE RING PAINTS. Never the
                        // head angle — the preview is mirrored and ML Kit's
                        // sign convention is not worth guessing at. This way
                        // the chevrons cannot contradict the ring, and if the
                        // ring is ever found to fill the wrong way round on a
                        // real handset, that is ONE fix in the controller's
                        // index mapping and these follow it for free.
                        const SizedBox(height: 18),
                        ValueListenableBuilder<List<bool>>(
                          valueListenable: ring.lit,
                          builder: (_, List<bool> lit, Widget? child) =>
                              LivenessArrows(lit: lit),
                        ),
                      ],
                    );
                  },
                ),
              ),

              // ── THE HINT ────────────────────────────────────────────────
              //
              // ⚠ ONE VOICE AT A TIME. The ring owns the words until it is
              // finished, then the framing guidance takes over, and neither
              // speaks while a failure is being explained. Three panels
              // shouting at once is what this screen looked like before.
              Positioned(
                top: 18,
                left: 20,
                right: 20,
                child: ValueListenableBuilder<LivenessRingState>(
                  valueListenable: ring.state,
                  builder: (_, LivenessRingState st, Widget? child) {
                    if (ring.failureReason.value.isNotEmpty) {
                      return const SizedBox.shrink();
                    }
                    final bool sweeping = st != LivenessRingState.complete;
                    return ValueListenableBuilder<bool>(
                      valueListenable: auto.gaveUp,
                      builder: (_, bool up, Widget? child) {
                        if (up) return const SizedBox.shrink();
                        return ValueListenableBuilder<String>(
                          valueListenable:
                              sweeping ? ring.hint : auto.guidance,
                          builder: (_, String msg, Widget? child) => _pill(msg),
                        );
                      },
                    );
                  },
                ),
              ),

              // ── START ───────────────────────────────────────────────────
              //
              // Shown only in `ready`, so the sweep — and its clock — begin
              // when the person says so and not when their face happens to
              // drift into centre.
              Positioned(
                left: 24,
                right: 24,
                bottom: 24,
                child: ValueListenableBuilder<LivenessRingState>(
                  valueListenable: ring.state,
                  builder: (_, LivenessRingState st, Widget? child) {
                    if (st != LivenessRingState.ready) {
                      return const SizedBox.shrink();
                    }
                    return FilledButton(
                      onPressed: ring.start,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        backgroundColor: _kBrand,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26)),
                      ),
                      child: const Text('Start',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    );
                  },
                ),
              ),

              // ── WHY IT DID NOT FINISH, AND THE WAY BACK ─────────────────
              Positioned(
                left: 20,
                right: 20,
                bottom: 92,
                child: ValueListenableBuilder<String>(
                  valueListenable: ring.failureReason,
                  builder: (_, String reason, Widget? child) {
                    if (reason.isEmpty) return const SizedBox.shrink();
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            'The movement check did not finish',
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white),
                          ),
                          const SizedBox(height: 5),
                          Text(reason,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.45,
                                  color:
                                      Colors.white.withValues(alpha: 0.85))),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _retry,
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text(
                                'Try the movement check again',
                                style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700),
                              ),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(double.infinity, 44),
                                backgroundColor: _kGreen,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(22)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              if (_checking)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
            ],
          ),
        ),

        // ── THE MANUAL SHUTTER ────────────────────────────────────────────
        //
        // ⚠ ALWAYS PRESENT, NEVER DISABLED BY A CHECK. Auto-capture is a
        // convenience; this is the guarantee that nobody is trapped on this
        // screen by a camera, a face detector or a phone we did not anticipate.
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
          child: FilledButton(
            onPressed: _checking ? null : _manualShutter,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 54),
              backgroundColor: _kBrand,
              foregroundColor: Colors.white,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            ),
            child: const Text('Take Selfie',
                style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _pill(String msg) => AnimatedOpacity(
        opacity: msg.isEmpty ? 0 : 1,
        duration: const Duration(milliseconds: 180),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            msg,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
          ),
        ),
      );
}
