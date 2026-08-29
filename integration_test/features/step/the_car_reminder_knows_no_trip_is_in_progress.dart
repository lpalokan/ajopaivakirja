import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then the car reminder knows no trip is in progress
Future<void> theCarReminderKnowsNoTripIsInProgress(WidgetTester tester) async {
  expectMirroredTripActive(false);
}
