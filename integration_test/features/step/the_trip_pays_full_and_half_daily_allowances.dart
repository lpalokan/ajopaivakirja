import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then the trip pays {2} full and {0} half daily allowances
Future<void> theTripPaysFullAndHalfDailyAllowances(
  WidgetTester tester,
  int full,
  int half,
) async {
  await expectDailyAllowances(tester, full: full, half: half);
}
