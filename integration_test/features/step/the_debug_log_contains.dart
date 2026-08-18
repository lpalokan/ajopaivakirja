import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then the debug log contains {'Reminder: tick'}
Future<void> theDebugLogContains(WidgetTester tester, String text) async {
  await expectDebugLogContains(tester, text);
}
