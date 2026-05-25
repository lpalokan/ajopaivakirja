import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then no arrival reminder has been shown
Future<void> noArrivalReminderHasBeenShown(WidgetTester tester) async {
  expectArrivalReminderShownCount(0);
}
