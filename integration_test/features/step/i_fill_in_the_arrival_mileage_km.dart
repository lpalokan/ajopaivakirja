import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: And I fill in the arrival mileage {int} km
///
/// Assumes the arrival dialog is already open (e.g. opened by the
/// notification "Olen perillä" action). Enters the odometer and saves.
Future<void> iFillInTheArrivalMileageKm(WidgetTester tester, int km) async {
  await fillArrivalDialog(tester, km);
}
