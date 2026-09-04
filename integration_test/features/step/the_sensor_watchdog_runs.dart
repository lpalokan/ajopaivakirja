import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When the sensor watchdog runs
Future<void> theSensorWatchdogRuns(WidgetTester tester) async {
  await waitForSensorWatchdog(tester);
}
