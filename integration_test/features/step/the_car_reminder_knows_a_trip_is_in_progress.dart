import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then the car reminder knows a trip is in progress
Future<void> theCarReminderKnowsATripIsInProgress(WidgetTester tester) async {
  expectMirroredTripActive(true);
}
