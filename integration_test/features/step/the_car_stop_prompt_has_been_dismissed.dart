import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then the car stop prompt has been dismissed
Future<void> theCarStopPromptHasBeenDismissed(WidgetTester tester) async {
  expectCarStopPromptDismissed();
}
