import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Given the update service reports {'up_to_date'}
Future<void> theUpdateServiceReports(
  WidgetTester tester,
  String mode,
) async {
  setUpdateServiceMode(mode);
}
