import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Given the app is running
Future<void> theAppIsRunning(WidgetTester tester) async {
  await launchApp(tester);
}
