import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Given cancelling the driving notification fails
///
/// Makes one step of the trip teardown throw, the way a platform channel
/// can. Which step it is matters less than where it sits in the sequence:
/// it runs between the trip ending and the GPS being released, so before
/// the guards it took the location foreground service down with it.
Future<void> cancellingTheDrivingNotificationFails(WidgetTester tester) async {
  failDrivingNotificationCancel();
}
