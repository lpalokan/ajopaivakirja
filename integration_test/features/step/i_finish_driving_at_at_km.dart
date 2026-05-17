import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When I finish driving at {string} at {int} km
Future<void> iFinishDrivingAtAtKm(
    WidgetTester tester, String to, int km) async {
  await arriveAdHoc(tester, to, km);
}
