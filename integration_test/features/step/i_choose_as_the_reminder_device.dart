import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When I choose {string} as the reminder device
Future<void> iChooseAsTheReminderDevice(
  WidgetTester tester,
  String label,
) async {
  await chooseReminderDevice(tester, label);
}
