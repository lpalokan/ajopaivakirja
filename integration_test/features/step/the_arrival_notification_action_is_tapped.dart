import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: And the arrival notification action is tapped
Future<void> theArrivalNotificationActionIsTapped(WidgetTester tester) async {
  await tapArrivalAction(tester);
}
