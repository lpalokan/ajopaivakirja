import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When I toggle debug logging
Future<void> iToggleDebugLogging(WidgetTester tester) async {
  await toggleDebugLogging(tester);
}
