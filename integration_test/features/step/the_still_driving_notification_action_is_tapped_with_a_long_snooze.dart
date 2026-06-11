import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: And the still driving notification action is tapped with a long snooze
///
/// Same background-isolate tap path as the plain step, but with a snooze
/// window pushed far beyond any pump a scenario performs — so "reminders
/// stay silent for the whole snooze window" can be asserted.
Future<void> theStillDrivingNotificationActionIsTappedWithALongSnooze(
  WidgetTester tester,
) async {
  await tapStillDrivingAction(tester, snooze: const Duration(seconds: 60));
}
