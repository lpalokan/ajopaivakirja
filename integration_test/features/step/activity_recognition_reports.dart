import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When activity recognition reports {'in_vehicle'}
Future<void> activityRecognitionReports(
  WidgetTester tester,
  String activity,
) async {
  await pushActivity(tester, activity);
}
