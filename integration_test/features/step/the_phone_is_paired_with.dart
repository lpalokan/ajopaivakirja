import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Given the phone is paired with {string}
Future<void> thePhoneIsPairedWith(WidgetTester tester, String name) async {
  addPairedDevice(name);
}
