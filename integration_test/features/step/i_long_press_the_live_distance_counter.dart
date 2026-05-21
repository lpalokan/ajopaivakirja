import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When I long press the live distance counter
Future<void> iLongPressTheLiveDistanceCounter(WidgetTester tester) async {
  await longPressLiveCounter(tester);
}
