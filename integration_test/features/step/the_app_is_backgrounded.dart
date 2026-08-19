import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When the app is backgrounded
Future<void> theAppIsBackgrounded(WidgetTester tester) async {
  await appIsBackgrounded(tester);
}
