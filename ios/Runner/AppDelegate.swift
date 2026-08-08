import Flutter
import UIKit
import FirebaseAuth
import FirebaseCore

// ─────────────────────────────────────────────────────────────────────────────
//  FIREBASE PHONE AUTH ON iOS NEEDS NATIVE CODE. THIS FILE HAD NONE.
//
//  Fixed 8 August 2026, after "silent reCAPTCHA" — the reCAPTCHA page appears,
//  the host completes it, and the app never moves.
//
//  This file was the bare `flutter create` default. All four hooks Firebase
//  Phone Auth requires were missing, and their absence is invisible to the
//  compiler, the analyzer and the build.
//
//  ── HOW PHONE AUTH ACTUALLY WORKS, AND WHERE IT WAS BROKEN ─────────────────
//
//  Before Firebase will send an SMS it must prove the request came from THIS
//  app. It tries two things, in order:
//
//  1. SILENT APNs PUSH. Firebase sends a push nobody sees, and the app proving
//     it received it is the verification. Three things are needed:
//
//       registerForRemoteNotifications()      ← WAS MISSING. Without it the
//                                               app never asks iOS for a
//                                               token, so no push can ever
//                                               arrive. The silent path was
//                                               dead before it started.
//       setAPNSToken(...)                     ← WAS MISSING. Even with a
//                                               token, Firebase never saw it.
//       canHandleNotification(...)            ← WAS MISSING. Even if a push
//                                               arrived, it was never handed
//                                               to Firebase Auth.
//
//     Info.plist already had UIBackgroundModes: remote-notification, and
//     Runner.entitlements already had aps-environment. Both were correct and
//     both were useless without the three calls above — which is exactly the
//     kind of gap that looks configured and is not.
//
//  2. reCAPTCHA FALLBACK. When the silent push does not arrive, Firebase opens
//     a reCAPTCHA web view. On completion it re-opens the app through the
//     REVERSED_CLIENT_ID URL scheme, which IS registered in Info.plist.
//
//       Auth.auth().canHandle(url)            ← WAS MISSING.
//
//     So the callback URL arrived, iOS brought the app forward, and nothing
//     consumed it. To the host: they solved the puzzle and the screen froze.
//     THAT is the reported bug.
//
//  Because hook 1 was entirely missing, EVERY host was forced down path 2 —
//  and path 2 was broken. Signup working at all was luck.
//
//  ── WHAT IS DELIBERATELY *NOT* COPIED FROM driver_app ──────────────────────
//
//  driver_app's AppDelegate wipes the Keychain on every launch. That is a
//  temporary diagnostic for an unrelated OOM crash, marked in its own comments
//  as "must be reverted before shipping to real users — it currently signs
//  everyone out on every app open". Copying it here would sign every host out
//  every time they opened the app.
//
//  ── ALSO SEE SceneDelegate.swift ───────────────────────────────────────────
//
//  This app is UIScene-based (Info.plist has UIApplicationSceneManifest). On a
//  scene-based app iOS delivers opened URLs to the SCENE delegate, not to
//  application(_:open:options:) below. The URL handler is implemented in both
//  places on purpose — see the note in SceneDelegate.swift.
// ─────────────────────────────────────────────────────────────────────────────

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  // ── ⚠ THIS IS WHY BUILD 8 CRASHED ON LAUNCH ──────────────────────────────
  //
  // Fixed 9 August 2026. Build 8 died instantly, every time, on open.
  //
  // Touching `Auth.auth()` before FirebaseApp.configure() has run is not an
  // error you can catch. It is a hard assertion inside the Firebase SDK:
  //
  //     "The default FirebaseApp instance must be configured before the
  //      default Auth instance can be initialized."
  //
  // Nothing configures Firebase in this file. firebase_core's iOS plugin does
  // it, during plugin registration — and THIS app registers plugins in
  // didInitializeImplicitFlutterEngine below, which iOS calls only once the
  // Flutter engine spins up, AFTER didFinishLaunching has returned.
  //
  // Build 8 asked iOS for an APNs token as the first line of didFinishLaunching.
  // On a device that already has a token cached — which is every device that
  // ran build 7 — iOS calls back almost immediately, we called Auth.auth(),
  // and Firebase was not up yet. Crash, before a single frame drew.
  //
  // driver_app never hit this because it uses the OLDER Flutter template and
  // registers plugins synchronously, on the line above the APNs call:
  //
  //     GeneratedPluginRegistrant.register(with: self)   ← Firebase configured
  //     application.registerForRemoteNotifications()     ← only then
  //
  // Same four hooks, opposite order, completely different outcome. Copying the
  // hooks across without copying the ORDER is the whole bug.
  //
  // ── THE FIX IS NOT "PUT IT BACK IN THE OLD ORDER" ─────────────────────────
  //
  // That would trade one timing assumption for another. Instead the token is
  // held until Firebase is genuinely ready, and every Auth call in this file is
  // guarded. The ordering can now change again — a Flutter upgrade, a template
  // regeneration — without this coming back.
  private var pendingAPNSToken: Data?
  private var apnsRetries = 0

  /// True only once firebase_core has configured the default app.
  private var firebaseReady: Bool { FirebaseApp.app() != nil }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // super FIRST. It starts the Flutter engine, and the engine starting is
    // what eventually registers the plugins. Asking for the APNs token before
    // this is what created the race.
    let started = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // Ask iOS for an APNs token so Firebase can use the silent-push path.
    //
    // This does NOT show a permission prompt. A silent push needs no user
    // consent — only visible alerts do. The host sees nothing.
    application.registerForRemoteNotifications()

    return started
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Firebase is configured as of the line above. If iOS already handed us a
    // token while we were still starting, this is the moment it becomes safe
    // to use — no polling, no guessing.
    if let token = pendingAPNSToken { applyAPNSToken(token) }
  }

  /// Hands the APNs token to Firebase Auth, or holds it until Firebase exists.
  ///
  /// Phone auth genuinely needs this token — dropping it silently would put us
  /// back on the broken reCAPTCHA path that build 8 set out to fix. So it is
  /// deferred, never discarded.
  private func applyAPNSToken(_ token: Data) {
    guard firebaseReady else {
      pendingAPNSToken = token

      // Backstop for the case where didInitializeImplicitFlutterEngine is not
      // called at all (an older Flutter, a regenerated template). Bounded, so a
      // genuinely broken Firebase config cannot spin forever.
      guard apnsRetries < 20 else {
        NSLog("[GoOutsHost] Firebase never configured — APNs token dropped. "
              + "Phone auth will fall back to reCAPTCHA.")
        return
      }
      apnsRetries += 1
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
        guard let self, let held = self.pendingAPNSToken else { return }
        self.applyAPNSToken(held)
      }
      return
    }

    pendingAPNSToken = nil
    Auth.auth().setAPNSToken(token, type: .prod)
  }

  // ── APNs token → Firebase Auth ───────────────────────────────────────────
  //
  // .prod, not .unknown. Every build of this app is produced by GitHub Actions
  // and distributed through TestFlight, which is always the PRODUCTION APNs
  // environment. driver_app went through roughly twenty builds discovering
  // that letting Firebase auto-detect the environment was the variable worth
  // removing.
  //
  // ⚠ If anyone ever runs a debug build from Xcode on a device, this must be
  // .sandbox for that build or phone auth will fail on it. Nothing in this
  // project does that today — there is no Mac in the loop.
  override func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    // Was `Auth.auth().setAPNSToken(...)` directly. On a device with a cached
    // token this fires before Firebase exists — that was the crash.
    applyAPNSToken(deviceToken)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  // Registration can fail — no network at launch, a provisioning profile
  // without the push entitlement, Simulator. Logged rather than swallowed:
  // when phone auth misbehaves this line is the difference between "APNs never
  // registered" and half a day of guessing.
  override func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
    NSLog("[GoOutsHost] APNs registration FAILED: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  // ── Silent push → Firebase Auth ──────────────────────────────────────────
  //
  // Returning early when Firebase claims the notification is required. Passing
  // an auth push on to super as well makes Flutter's messaging plugin try to
  // deliver a notification that has no user-facing content.
  override func application(_ application: UIApplication,
                            didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                            fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    // firebaseReady guard: a silent push can be delivered to a cold-launched
    // app before the engine is up. Same crash as the token path.
    if firebaseReady, Auth.auth().canHandleNotification(userInfo) {
      completionHandler(.noData)
      return
    }
    super.application(application, didReceiveRemoteNotification: userInfo,
                      fetchCompletionHandler: completionHandler)
  }

  // ── reCAPTCHA callback URL → Firebase Auth ───────────────────────────────
  //
  // THE FIX FOR THE REPORTED BUG, on the non-scene path.
  //
  // iOS does not call this on a UIScene-based app — SceneDelegate gets it
  // instead. It stays because it costs nothing, because Flutter's scene
  // support is new enough that the routing has changed between versions, and
  // because the failure mode if the wrong one is implemented is a screen that
  // silently never moves.
  override func application(_ application: UIApplication,
                            open url: URL,
                            options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    if firebaseReady, Auth.auth().canHandle(url) { return true }
    return super.application(application, open: url, options: options)
  }
}
