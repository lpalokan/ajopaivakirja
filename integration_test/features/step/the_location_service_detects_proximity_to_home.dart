import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When the location service detects proximity to home
Future<void> theLocationServiceDetectsProximityToHome(
  WidgetTester tester,
) async {
  await simulateNearHomeProximity(tester);
}
