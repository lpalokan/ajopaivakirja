import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Given GPS reports driving speed
///
/// Starts a continuous feed of position fixes at motorway speed, the way a
/// real position stream behaves during a drive. This is the signal that must
/// keep "Oletko perillä?" silent no matter what Activity Recognition claims.
Future<void> gpsReportsDrivingSpeed(WidgetTester tester) async {
  setGpsDrivingSpeed();
}
