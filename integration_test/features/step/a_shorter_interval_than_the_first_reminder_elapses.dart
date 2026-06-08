import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When a shorter interval than the first reminder elapses
Future<void> aShorterIntervalThanTheFirstReminderElapses(
  WidgetTester tester,
) async {
  await waitShorterThanFirstReminder(tester);
}
