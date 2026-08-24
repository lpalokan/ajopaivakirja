import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When I start a free trip at {1000} km
Future<void> iStartAFreeTripAtKm(WidgetTester tester, int odometer) async {
  await startFreeTrip(tester, odometer);
}
