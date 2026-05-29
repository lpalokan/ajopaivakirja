import 'package:flutter_test/flutter_test.dart';
import '../../support/harness.dart';

/// Usage: Given location permission is granted
Future<void> locationPermissionIsGranted(WidgetTester tester) async {
  grantLocationPermission();
}
