import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then the app does not remember the place {'Koti'}
Future<void> theAppDoesNotRememberThePlace(
  WidgetTester tester,
  String name,
) async {
  await expectPlaceNotRemembered(tester, name);
}
