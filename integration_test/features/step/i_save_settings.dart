import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When I save settings
Future<void> iSaveSettings(WidgetTester tester) async {
  await saveSettings(tester);
}
