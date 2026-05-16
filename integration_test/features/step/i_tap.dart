import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When I tap {string}
Future<void> iTap(WidgetTester tester, String text) async {
  await tapText(tester, text);
}
