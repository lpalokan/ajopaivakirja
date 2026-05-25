import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When the reminder backstop elapses
Future<void> theReminderBackstopElapses(WidgetTester tester) async {
  await waitForReminderBackstop(tester);
}
