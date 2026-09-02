import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When the sensor stand down delay elapses
Future<void> theSensorStandDownDelayElapses(WidgetTester tester) async {
  await waitForSensorStandDown(tester);
}
