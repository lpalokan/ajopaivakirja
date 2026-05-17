import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then the file was opened in an external app
Future<void> theFileWasOpenedInAnExternalApp(WidgetTester tester) async {
  await expectFileOpened(tester);
}
