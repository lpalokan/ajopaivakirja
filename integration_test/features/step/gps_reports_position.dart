import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When GPS reports position {60.2} {24.65}
Future<void> gpsReportsPosition(
  WidgetTester tester,
  double latitude,
  double longitude,
) async {
  await reportGpsPosition(tester, latitude, longitude);
}
