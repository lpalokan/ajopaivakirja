import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When I start an ad-hoc trip from {string} at {int} km
Future<void> iStartAnAdhocTripFromAtKm(
    WidgetTester tester, String from, int km) async {
  await startAdHoc(tester, from, km);
}
