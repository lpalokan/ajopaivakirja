import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then the {string} setting is {string}
Future<void> theSettingIs(
    WidgetTester tester, String key, String value) async {
  await expectSetting(tester, key, value);
}
