import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then the car reminder has no movement evidence
Future<void> theCarReminderHasNoMovementEvidence(WidgetTester tester) async {
  expectCarMovementEvidence(false);
}
