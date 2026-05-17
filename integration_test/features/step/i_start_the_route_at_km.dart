import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When I start the {string} route at {int} km
Future<void> iStartTheRouteAtKm(
    WidgetTester tester, String route, int km) async {
  await startTrip(tester, route, km);
}
