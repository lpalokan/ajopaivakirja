import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When I enter {string} in the {string} field
Future<void> iEnterInTheField(
    WidgetTester tester, String value, String label) async {
  await enterSettingsField(tester, value, label);
}
