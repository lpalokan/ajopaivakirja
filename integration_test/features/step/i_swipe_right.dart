import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When I swipe {string} right
Future<void> iSwipeRight(WidgetTester tester, String text) async {
  await swipeRight(tester, text);
}
