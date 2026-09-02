import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then the app is tracking location for the trip
///
/// The trip's own position stream is open, i.e. the location foreground
/// service that keeps fixes arriving with the screen locked.
Future<void> theAppIsTrackingLocationForTheTrip(WidgetTester tester) async {
  await expectTrackingLocationForTrip(tester);
}
