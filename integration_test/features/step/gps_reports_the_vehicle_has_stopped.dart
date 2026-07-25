import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When GPS reports the vehicle has stopped
///
/// Keeps the position feed running but drops the speed to zero, so the
/// movement signal goes stale and the reminder becomes reachable again.
Future<void> gpsReportsTheVehicleHasStopped(WidgetTester tester) async {
  setGpsStopped();
}
