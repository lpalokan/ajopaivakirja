import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then the car reminder does not think I am home for the day
Future<void> theCarReminderDoesNotThinkIAmHomeForTheDay(
  WidgetTester tester,
) async {
  expectMirroredHomeToday(false);
}
