import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Given I am signed in to Google
Future<void> iAmSignedInToGoogle(WidgetTester tester) async {
  signInToGoogle();
}
