import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When I add route {string} from {string} to {string} of {int} km
Future<void> iAddRouteFromToOfKm(WidgetTester tester, String name,
    String from, String to, int km) async {
  await addRoute(tester, name, from, to, km);
}
