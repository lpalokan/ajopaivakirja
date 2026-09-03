import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: And the sensor diagnostics do not show {'Kotinäkymän sijaintiseuranta'}
Future<void> theSensorDiagnosticsDoNotShow(
  WidgetTester tester,
  String what,
) async {
  expectSensorDiagnosticsDoNotShow(what);
}
