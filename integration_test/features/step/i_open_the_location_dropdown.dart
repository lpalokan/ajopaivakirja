import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When I open the {string} location dropdown
Future<void> iOpenTheLocationDropdown(WidgetTester tester, String label) async {
  await openLocationDropdown(tester, label);
}
