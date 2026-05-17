import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When I tap the {string} dialog button
Future<void> iTapTheDialogButton(WidgetTester tester, String label) async {
  await tapDialogButton(tester, label);
}
