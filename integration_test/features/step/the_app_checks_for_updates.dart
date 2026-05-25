import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When the app checks for updates
Future<void> theAppChecksForUpdates(WidgetTester tester) async {
  await triggerUpdateCheck(tester);
}
