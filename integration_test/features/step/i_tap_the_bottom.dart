import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When I tap the bottom {string}
Future<void> iTapTheBottom(WidgetTester tester, String label) async {
  await tapBottomArriveButton(tester);
}
