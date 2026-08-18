import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Given debug logging is enabled
Future<void> debugLoggingIsEnabled(WidgetTester tester) async {
  await enableDebugLogging(tester);
}
