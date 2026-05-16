import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then I do not see {string}
Future<void> iDoNotSee(WidgetTester tester, String text) async {
  await expectAbsent(tester, text);
}
