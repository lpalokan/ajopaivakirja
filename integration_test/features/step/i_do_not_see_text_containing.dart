import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then I do not see text containing {string}
Future<void> iDoNotSeeTextContaining(WidgetTester tester, String text) async {
  await expectNotContains(tester, text);
}
