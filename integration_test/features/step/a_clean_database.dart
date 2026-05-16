import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Given a clean database
Future<void> aCleanDatabase(WidgetTester tester) async {
  await resetDatabase();
}
