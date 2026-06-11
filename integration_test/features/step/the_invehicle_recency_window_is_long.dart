import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: And the in-vehicle recency window is long
///
/// Pushes BackgroundService's in-vehicle recency window far beyond the pump
/// budget, so a scenario can assert that a confident non-vehicle reading
/// shortly after `in_vehicle` (a red light, a bump) does NOT fire the
/// reminder. The harness default window is shorter than one steady-state
/// poll so the other scenarios still observe prompt re-asks.
Future<void> theInvehicleRecencyWindowIsLong(WidgetTester tester) async {
  setLongInVehicleRecencyWindow();
}
