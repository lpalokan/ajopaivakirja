import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then the odometer field shows {int} km
Future<void> theOdometerFieldShowsKm(WidgetTester tester, int km) async {
  await expectOdometerFieldValue(tester, km);
}
