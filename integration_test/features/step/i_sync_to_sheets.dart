import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When I sync to sheets
Future<void> iSyncToSheets(WidgetTester tester) async {
  await syncToSheets(tester);
}
