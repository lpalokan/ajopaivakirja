import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then the {string} field shows {string}
Future<void> theFieldShows(
  WidgetTester tester,
  String label,
  String value,
) async {
  await expectLocationFieldValue(tester, label, value);
}
