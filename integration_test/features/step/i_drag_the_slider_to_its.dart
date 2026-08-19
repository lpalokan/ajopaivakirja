import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: When I drag the {'detection_speed'} slider to its {'maximum'}
Future<void> iDragTheSliderToIts(
  WidgetTester tester,
  String sliderKey,
  String extreme,
) async {
  await dragSliderToExtreme(tester, sliderKey, extreme);
}
