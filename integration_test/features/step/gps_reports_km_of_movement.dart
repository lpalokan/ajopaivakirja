import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When GPS reports {int} km of movement
Future<void> gpsReportsKmOfMovement(WidgetTester tester, int km) async {
  await simulateGpsMovement(tester, km.toDouble());
}
