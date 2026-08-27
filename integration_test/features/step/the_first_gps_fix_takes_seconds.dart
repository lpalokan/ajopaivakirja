import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Given the first GPS fix takes {20} seconds
Future<void> theFirstGpsFixTakesSeconds(
  WidgetTester tester,
  int seconds,
) async {
  setSlowFirstGpsFix(Duration(seconds: seconds));
}
