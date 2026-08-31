import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then the car reminder knows the vehicle was recently moving
Future<void> theCarReminderKnowsTheVehicleWasRecentlyMoving(
  WidgetTester tester,
) async {
  expectCarMovementEvidence(true);
}
