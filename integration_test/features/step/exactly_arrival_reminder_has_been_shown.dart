import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then exactly {int} arrival reminder has been shown
Future<void> exactlyArrivalReminderHasBeenShown(
  WidgetTester tester,
  int count,
) async {
  expectArrivalReminderShownCount(count);
}
