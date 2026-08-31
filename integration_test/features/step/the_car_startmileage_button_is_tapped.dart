import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/services/bluetooth_trigger_service.dart';
import '../../support/harness.dart';

/// Usage: And the car start-mileage button is tapped
Future<void> theCarStartmileageButtonIsTapped(WidgetTester tester) async {
  await tapCarMileageButton(tester, BluetoothTriggerService.logStartAction);
}
