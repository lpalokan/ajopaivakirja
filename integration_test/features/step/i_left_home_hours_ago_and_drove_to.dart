import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Given I left home {32} hours ago and drove to {'Työ'}
Future<void> iLeftHomeHoursAgoAndDroveTo(
  WidgetTester tester,
  int hoursAgo,
  String destination,
) async {
  await seedOutboundLeg(tester, hoursAgo: hoursAgo, destination: destination);
}
