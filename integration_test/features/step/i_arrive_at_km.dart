import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When I arrive at {int} km
Future<void> iArriveAtKm(WidgetTester tester, int km) async {
  await arrive(tester, km);
}
