import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: And the in-memory trip state is cleared
Future<void> theInmemoryTripStateIsCleared(WidgetTester tester) async {
  await clearInMemoryTripState(tester);
}
