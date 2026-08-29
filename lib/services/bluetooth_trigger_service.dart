import 'package:flutter/services.dart';

import 'log_service.dart';

/// A Bluetooth device the phone is already paired with.
class PairedDevice {
  /// The MAC address. Stable, and what the native receiver matches on.
  final String address;

  /// What the driver sees — the name the device advertises, which for a car
  /// is usually its model or the head unit's brand.
  final String name;

  const PairedDevice({required this.address, required this.name});

  /// Never show a bare MAC as a label: an address is not a thing anybody
  /// recognises as their car.
  String get label => name.trim().isEmpty ? address : name.trim();

  @override
  bool operator ==(Object other) =>
      other is PairedDevice && other.address == address && other.name == name;

  @override
  int get hashCode => Object.hash(address, name);

  @override
  String toString() => 'PairedDevice($label, $address)';
}

/// Start- and stop-driving reminders triggered by the car's Bluetooth.
///
/// Most cars pair with the phone when the ignition comes on and drop the link
/// when it goes off, which makes the connection a far better signal than
/// anything the app can work out for itself. It costs nothing to listen for:
/// `ACTION_ACL_CONNECTED` / `ACTION_ACL_DISCONNECTED` are on Android's
/// exemption list for the API 26+ implicit-broadcast restrictions, so a
/// manifest-declared receiver is delivered even when the app is not running.
/// No service, no wake lock, no GPS — which is exactly why this exists and
/// automatic GPS detection does not (#51).
///
/// The reminder fires from native code for that reason: when the car connects
/// there may be no Flutter engine to run. Everything the *driver* configures
/// lives here, and the chosen address is handed to the native side to store
/// where the receiver can read it without starting Dart.
class BluetoothTriggerService {
  static const MethodChannel channel = MethodChannel(
    'fi.lpalokan.kilometrikorvaus/bluetooth_trigger',
  );

  /// Whether this build can watch a Bluetooth device at all. False off
  /// Android, where the receiver does not exist.
  Future<bool> isSupported() async => await _call<bool>('isSupported') ?? false;

  /// Whether the "Nearby devices" permission (`BLUETOOTH_CONNECT`, Android 12+)
  /// has been granted. Without it the paired list comes back empty and the
  /// broadcast carries no device to match.
  Future<bool> hasPermission() async =>
      await _call<bool>('hasPermission') ?? false;

  /// Ask for "Nearby devices". Returns whether it ended up granted.
  Future<bool> requestPermission() async =>
      await _call<bool>('requestPermission') ?? false;

  /// Everything the phone is already paired with. Pairing is not this app's
  /// job — the car is paired in Android's own settings and merely picked here.
  Future<List<PairedDevice>> pairedDevices() async {
    final raw = await _call<List<Object?>>('pairedDevices');
    if (raw == null) return const [];
    return [
      for (final entry in raw)
        if (entry is Map && (entry['address']?.toString() ?? '').isNotEmpty)
          PairedDevice(
            address: entry['address'].toString(),
            name: entry['name']?.toString() ?? '',
          ),
    ];
  }

  /// The address currently set to trigger reminders, or null for "off".
  Future<String?> triggerAddress() => _call<String>('triggerAddress');

  /// Choose the device, or pass null to switch the reminders off.
  Future<void> setTriggerAddress(String? address) =>
      _call<void>('setTriggerAddress', {'address': address});

  /// Tell the native side whether a trip is open right now.
  ///
  /// The receiver has to decide, with no Flutter engine and no database, which
  /// of the two prompts is worth showing: "Aloititko ajon?" is noise if the
  /// driver already tapped Aloita ajo, and "Päättyikö ajo?" is noise if there
  /// is nothing to end. That is knowledge only the app has, so it is mirrored
  /// across as it changes — and re-asserted on every load, since the app can
  /// be killed mid-trip and the flag left stale.
  ///
  /// Also clears whichever reminder this makes moot: a "Aloititko ajon?"
  /// sitting in the shade after the trip has been started is exactly the
  /// nagging this is meant to remove.
  Future<void> setTripActive(bool active) =>
      _call<void>('setTripActive', {'active': active});

  /// Every channel call is best-effort: a missing plugin (host tests, iOS, an
  /// older build) must degrade to "not available", never take Settings down.
  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await channel.invokeMethod<T>(method, args);
    } catch (e) {
      LogService().warn('Bluetooth: $method failed: $e');
      return null;
    }
  }
}
