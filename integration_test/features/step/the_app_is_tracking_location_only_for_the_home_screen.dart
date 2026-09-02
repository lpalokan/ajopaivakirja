import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then the app is tracking location only for the home screen
///
/// The trip's foreground-service stream is down and the cheap idle watch —
/// the one that keeps the position chip honest while someone is looking at
/// it — has taken over.
Future<void> theAppIsTrackingLocationOnlyForTheHomeScreen(
  WidgetTester tester,
) async {
  await expectTrackingLocationOnlyForHomeScreen(tester);
}
