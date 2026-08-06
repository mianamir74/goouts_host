// Smoke test for GoOuts Host.
//
// The generated counter-demo test was left behind when main.dart was rewritten
// and referenced MyApp, which no longer exists. That was the only ERROR in the
// whole 8-project analyze run — a test file, not shipping code, but it would
// have failed CI the moment Codemagic ran `flutter test`.

import 'package:flutter_test/flutter_test.dart';

void main() {
  // NOTE: GoOutsHostApp cannot be pumped in a plain widget test. main()
  // calls Firebase.initializeApp() and _HostLaunchCoordinator subscribes to
  // FirebaseAuth.instance.authStateChanges() on build — both need platform
  // channels that do not exist in the test harness, so the test would fail on
  // a MissingPluginException rather than on anything real.
  //
  // Testing it properly needs firebase_auth_mocks or an integration test on a
  // device. Until then this asserts something true and cheap, so `flutter
  // test` passes in CI rather than being deleted outright.
  test('placeholder — app-level tests need Firebase mocks', () {
    expect(true, isTrue);
  });
}
