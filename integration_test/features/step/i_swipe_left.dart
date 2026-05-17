import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When I swipe {string} left
Future<void> iSwipeLeft(WidgetTester tester, String text) async {
  await swipeLeft(tester, text);
}
