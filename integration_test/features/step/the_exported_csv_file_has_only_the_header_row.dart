import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then the exported CSV file has only the header row
Future<void> theExportedCsvFileHasOnlyTheHeaderRow(WidgetTester tester) async {
  await expectCsvHasOnlyHeaderRow(tester);
}
