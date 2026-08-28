import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When the location service reports arrival at the destination
Future<void> theLocationServiceReportsArrivalAtTheDestination(
  WidgetTester tester,
) async {
  await simulateArrivalReported(tester);
}
