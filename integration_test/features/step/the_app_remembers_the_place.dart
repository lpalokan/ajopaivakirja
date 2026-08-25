import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Then the app remembers the place {'Työ'}
Future<void> theAppRemembersThePlace(WidgetTester tester, String name) async {
  await expectPlaceRemembered(tester, name);
}
