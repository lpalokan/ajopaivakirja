import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then the app is not tracking location
///
/// No platform location request of any kind is open — neither the trip's
/// foreground-service stream nor the home screen's cheap watch.
Future<void> theAppIsNotTrackingLocation(WidgetTester tester) async {
  await expectNotTrackingLocation(tester);
}
