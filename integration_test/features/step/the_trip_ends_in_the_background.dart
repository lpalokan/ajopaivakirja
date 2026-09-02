import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When the trip ends in the background
///
/// The arrival lands while no screen is up to host the mileage dialog, so
/// TripNotifier records the estimated odometer and closes the leg itself —
/// the production path behind an "Olen perillä" tap that the driver follows
/// by pocketing the phone.
Future<void> theTripEndsInTheBackground(WidgetTester tester) async {
  await endTripInBackground(tester);
}
