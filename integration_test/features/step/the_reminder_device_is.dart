import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then the reminder device is {string}
Future<void> theReminderDeviceIs(WidgetTester tester, String label) async {
  expectReminderDevice(label);
}
