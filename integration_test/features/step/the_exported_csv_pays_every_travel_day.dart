import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then the exported CSV pays every travel day
Future<void> theExportedCsvPaysEveryTravelDay(WidgetTester tester) async {
  await expectCsvPaysEveryTravelDay(tester);
}
