import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/services/bluetooth_trigger_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final channel = BluetoothTriggerService.channel;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Stand in for the Android side. Returning `_missing` makes the platform
  /// look absent, which is what a host test, an iOS build and an older
  /// install all look like from Dart.
  void answer(Object? Function(MethodCall call)? handler) {
    messenger.setMockMethodCallHandler(
      channel,
      handler == null ? null : (call) async => handler(call),
    );
  }

  tearDown(() => answer(null));

  group('PairedDevice', () {
    test('shows the name the car advertises', () {
      const device = PairedDevice(address: '00:11:22', name: 'Volvo V60');

      expect(device.label, 'Volvo V60');
    });

    test('falls back to the address when the name is missing', () {
      // A bare MAC is a poor label, but it is the only thing left — and it is
      // better than an empty row the driver cannot pick.
      const nameless = PairedDevice(address: '00:11:22', name: '   ');

      expect(nameless.label, '00:11:22');
    });
  });

  group('paired devices', () {
    test('are read back from the platform', () async {
      answer(
        (_) => [
          {'address': '00:11:22', 'name': 'Volvo V60'},
          {'address': 'AA:BB:CC', 'name': 'Kuulokkeet'},
        ],
      );

      final devices = await BluetoothTriggerService().pairedDevices();

      expect(devices.map((d) => d.label), ['Volvo V60', 'Kuulokkeet']);
      expect(devices.first.address, '00:11:22');
    });

    test('an entry with no address is dropped', () async {
      // Nothing can be matched against it later, so listing it would offer
      // the driver a choice that could never fire.
      answer(
        (_) => [
          {'address': '', 'name': 'Haamu'},
          {'address': '00:11:22', 'name': 'Volvo V60'},
        ],
      );

      final devices = await BluetoothTriggerService().pairedDevices();

      expect(devices.map((d) => d.label), ['Volvo V60']);
    });

    test('a platform that answers nothing yields no devices', () async {
      answer((_) => null);

      expect(await BluetoothTriggerService().pairedDevices(), isEmpty);
    });
  });

  group('when the platform is not there at all', () {
    // Host tests, iOS, an install predating the receiver. Settings has to
    // render, so every call degrades instead of throwing.
    test('nothing throws and nothing is supported', () async {
      answer(null);
      final service = BluetoothTriggerService();

      expect(await service.isSupported(), isFalse);
      expect(await service.hasPermission(), isFalse);
      expect(await service.requestPermission(), isFalse);
      expect(await service.pairedDevices(), isEmpty);
      expect(await service.triggerAddress(), isNull);
      await service.setTriggerAddress('00:11:22');
    });

    test('a platform exception is swallowed too', () async {
      answer((_) => throw PlatformException(code: 'boom'));

      expect(await BluetoothTriggerService().isSupported(), isFalse);
      expect(await BluetoothTriggerService().triggerAddress(), isNull);
    });
  });

  group('choosing a device', () {
    test('hands the address to the platform to store', () async {
      final calls = <MethodCall>[];
      answer((call) {
        calls.add(call);
        return null;
      });

      await BluetoothTriggerService().setTriggerAddress('00:11:22');

      expect(calls.single.method, 'setTriggerAddress');
      expect(calls.single.arguments, {'address': '00:11:22'});
    });

    test('switching off sends a null address, not an empty string', () async {
      // The native store treats null and blank alike, but sending the wrong
      // one would make "off" depend on that leniency.
      final calls = <MethodCall>[];
      answer((call) {
        calls.add(call);
        return null;
      });

      await BluetoothTriggerService().setTriggerAddress(null);

      expect(calls.single.arguments, {'address': null});
    });

    test('reads back what was stored', () async {
      answer((call) => call.method == 'triggerAddress' ? '00:11:22' : null);

      expect(await BluetoothTriggerService().triggerAddress(), '00:11:22');
    });
  });
}
