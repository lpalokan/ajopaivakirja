import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: And I fill in the start mileage {int} km
///
/// Assumes the start dialog opened by the car's connect prompt is already up.
Future<void> iFillInTheStartMileageKm(WidgetTester tester, int km) async {
  await fillStartDialog(tester, km);
}
