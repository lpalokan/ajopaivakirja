import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When I open the add route dialog
Future<void> iOpenTheAddRouteDialog(WidgetTester tester) async {
  await openAddRouteDialog(tester);
}
