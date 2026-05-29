import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: And the app returns to the foreground
Future<void> theAppReturnsToTheForeground(WidgetTester tester) async {
  await appReturnsToForeground(tester);
}
