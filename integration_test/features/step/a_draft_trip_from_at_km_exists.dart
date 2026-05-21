import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When a draft trip from {string} at {int} km exists
Future<void> aDraftTripFromAtKmExists(
  WidgetTester tester,
  String from,
  int km,
) async {
  await createDraftLeg(startLocation: from, startOdometer: km);
}
