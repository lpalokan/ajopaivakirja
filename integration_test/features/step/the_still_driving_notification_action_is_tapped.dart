import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: And the still-driving notification action is tapped
Future<void> theStillDrivingNotificationActionIsTapped(
  WidgetTester tester,
) async {
  await tapStillDrivingAction(tester);
}
