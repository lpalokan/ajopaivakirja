import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then the arrival dialog odometer field shows {int} km
Future<void> theArrivalDialogOdometerFieldShowsKm(
  WidgetTester tester,
  int km,
) async {
  await expectArrivalOdometerFieldValue(tester, km);
}
