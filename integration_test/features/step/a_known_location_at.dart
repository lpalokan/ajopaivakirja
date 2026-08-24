import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Given a known location {'Toimisto'} at {60.2} {24.65}
Future<void> aKnownLocationAt(
  WidgetTester tester,
  String name,
  double latitude,
  double longitude,
) async {
  await addKnownLocation(name, latitude, longitude);
}
