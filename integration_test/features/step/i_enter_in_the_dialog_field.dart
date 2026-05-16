import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When I enter {string} in the dialog {string} field
Future<void> iEnterInTheDialogField(
    WidgetTester tester, String value, String label) async {
  await enterDialogField(tester, value, label);
}
