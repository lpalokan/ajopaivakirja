import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When I go back
Future<void> iGoBack(WidgetTester tester) async {
  await goBack(tester);
}
