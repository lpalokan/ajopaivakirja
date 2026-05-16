import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then I see {string}
Future<void> iSee(WidgetTester tester, String text) async {
  await expectVisible(tester, text);
}
