import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then the sensor diagnostics show {'Ajon sijaintiseuranta'}
///
/// Asserts what Settings → Vianmääritys → Anturien käyttö would be naming as
/// a current holder — the answer to "who has the GPS on", which no battery
/// screen gives you.
Future<void> theSensorDiagnosticsShow(WidgetTester tester, String what) async {
  expectSensorDiagnosticsShow(what);
}
