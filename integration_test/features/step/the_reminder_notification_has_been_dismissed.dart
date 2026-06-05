import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then the reminder notification has been dismissed
Future<void> theReminderNotificationHasBeenDismissed(
  WidgetTester tester,
) async {
  expectReminderDismissed();
}
