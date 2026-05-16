import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then I see text containing {string}
Future<void> iSeeTextContaining(WidgetTester tester, String text) async {
  await expectContains(tester, text);
}
