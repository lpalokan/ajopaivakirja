import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When I toggle {string}
Future<void> iToggle(WidgetTester tester, String label) async {
  await toggleSwitch(tester, label);
}
