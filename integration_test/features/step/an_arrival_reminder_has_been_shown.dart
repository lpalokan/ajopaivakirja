import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then an arrival reminder has been shown
Future<void> anArrivalReminderHasBeenShown(WidgetTester tester) async {
  expectArrivalReminderShownAtLeastOnce();
}
