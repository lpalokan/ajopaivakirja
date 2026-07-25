import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Given the configured spreadsheet is no longer accessible
///
/// Mimics the post-migration state: a `sheet_id` left over from the old
/// hand-picked spreadsheet, which the `drive.file` scope no longer grants
/// access to. The next sync must create a replacement.
Future<void> theConfiguredSpreadsheetIsNoLongerAccessible(
  WidgetTester tester,
) async {
  denySpreadsheetAccess();
}
