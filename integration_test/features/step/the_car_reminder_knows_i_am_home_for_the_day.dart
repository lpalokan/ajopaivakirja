import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then the car reminder knows I am home for the day
Future<void> theCarReminderKnowsIAmHomeForTheDay(WidgetTester tester) async {
  expectMirroredHomeToday(true);
}
