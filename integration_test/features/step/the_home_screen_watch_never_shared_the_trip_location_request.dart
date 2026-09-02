import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then the home screen watch never shared the trip location request
///
/// geolocator hands every caller the same platform request and only tears it
/// down when the LAST listener cancels, so a home-screen watch opened while
/// the trip's stream is up does not get a cheap request of its own — it
/// inherits, and then outlives, the trip's.
Future<void> theHomeScreenWatchNeverSharedTheTripLocationRequest(
  WidgetTester tester,
) async {
  expectNoWatchOpenedOnTopOfTheTrip();
}
