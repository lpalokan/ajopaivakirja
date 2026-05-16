import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When I open settings
Future<void> iOpenSettings(WidgetTester tester) async {
  await openSettings(tester);
}
