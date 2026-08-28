import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then no reminder device is set
Future<void> noReminderDeviceIsSet(WidgetTester tester) async {
  expectReminderDevice(null);
}
