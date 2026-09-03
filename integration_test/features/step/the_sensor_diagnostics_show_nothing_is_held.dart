import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then the sensor diagnostics show nothing is held
///
/// The state the app must be in whenever nobody is looking at it and no trip
/// is running. Eight hours of GPS in a battery report is this assertion
/// failing on a real phone.
Future<void> theSensorDiagnosticsShowNothingIsHeld(WidgetTester tester) async {
  expectNothingHeld();
}
