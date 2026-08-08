import Flutter
import UIKit
import FirebaseAuth

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
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Ask iOS for an APNs token so Firebase can use the silent-push path.
    //
    // This does NOT show a permission prompt. A silent push needs no user
    // consent — only visible alerts do. The host sees nothing.
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
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
    Auth.auth().setAPNSToken(deviceToken, type: .prod)
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
    if Auth.auth().canHandleNotification(userInfo) {
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
    if Auth.auth().canHandle(url) { return true }
    return super.application(application, open: url, options: options)
  }
}
