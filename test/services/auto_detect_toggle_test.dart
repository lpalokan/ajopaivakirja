import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/models/app_settings.dart';
import 'package:kilometrikorvaus/providers/settings_provider.dart';
import 'package:kilometrikorvaus/services/location_service.dart';
import 'package:kilometrikorvaus/services/notification_service.dart';
import 'package:kilometrikorvaus/services/trip_detection_service.dart';

/// A LocationService that always says yes, so a detection start that is
/// refused was refused by the setting and by nothing else.
class _PermissiveLocationService extends LocationService {
  @override
  Future<bool> hasPermissionGranted() async => true;
}

TripDetectionService _service() => TripDetectionService(
  locationService: _PermissiveLocationService(),
  notificationService: NotificationService(),
);

void main() {
  group('the auto_detect setting', () {
    test('is on unless the driver has turned it off', () {
      expect(const AppSettings().autoDetect, isTrue);
      expect(AppSettings.fromMap(const {}).autoDetect, isTrue);
    });

    test('an install that predates the toggle keeps detecting', () {
      // The key is simply absent in those databases; absent must not read as
      // "off" and silently take a feature away.
      final settings = AppSettings.fromMap(const {'home_location': 'Koti'});

      expect(settings.autoDetect, isTrue);
    });

    test('round-trips through the settings table', () {
      const off = AppSettings(autoDetect: false);

      expect(off.toMap()['auto_detect'], '0');
      expect(AppSettings.fromMap(off.toMap()).autoDetect, isFalse);
      expect(
        AppSettings.fromMap(const AppSettings().toMap()).autoDetect,
        isTrue,
      );
    });

    test('survives copyWith untouched', () {
      const off = AppSettings(autoDetect: false);

      expect(off.copyWith(kmRate: 0.6).autoDetect, isFalse);
      expect(off.copyWith(autoDetect: true).autoDetect, isTrue);
    });
  });

  group('the settings form', () {
    /// Drive SettingsNotifier.update the way the Settings screen's save
    /// button does. `save` assigns state before it touches the database, so
    /// the persistence failure a host test hits does not hide the mapping —
    /// which is the part that was broken.
    Future<AppSettings> applied(Map<String, String?> fields) async {
      final notifier = SettingsNotifier();
      try {
        await notifier.update(fields);
      } catch (_) {
        // No sqflite on the host; the mapping has already run.
      }
      return notifier.state;
    }

    test('applies the auto-detection switch', () async {
      // The emulator suite caught this: update() maps each known key onto
      // copyWith by hand, and a key with no branch is silently dropped — so
      // the switch moved, the form submitted, and the database still said
      // "on".
      expect((await applied({'auto_detect': '0'})).autoDetect, isFalse);
      expect((await applied({'auto_detect': '1'})).autoDetect, isTrue);
    });

    test('leaves the switch alone when the form does not mention it', () async {
      expect((await applied({'driver_name': 'Matti'})).autoDetect, isTrue);
    });

    test('carries every other key the form writes', () async {
      // The same silent-drop bug in any of these would be just as invisible.
      final settings = await applied({
        'home_location': 'Saunatie 9',
        'km_rate': '0.62',
        'allowance_6h': '20.0',
        'allowance_10h': '48.0',
        'sheet_tab': 'Matkat2026',
        'driver_name': 'Matti',
        'auto_detect': '0',
        'detection_speed_mps': '7.0',
        'detection_driving_seconds': '90',
        'detection_arrival_seconds': '150',
      });

      expect(settings.homeLocation, 'Saunatie 9');
      expect(settings.kmRate, 0.62);
      expect(settings.allowance6h, 20.0);
      expect(settings.allowance10h, 48.0);
      expect(settings.sheetTab, 'Matkat2026');
      expect(settings.driverName, 'Matti');
      expect(settings.autoDetect, isFalse);
      expect(settings.detectionSpeedMps, 7.0);
      expect(settings.detectionDrivingSeconds, 90);
      expect(settings.detectionArrivalSeconds, 150);
    });
  });

  group('detection honours the setting', () {
    test('a disabled detector never starts monitoring', () async {
      final service = _service();
      service.updateSettings(const AppSettings(autoDetect: false));

      await service.start();

      expect(service.state, DetectionState.idle);
    });

    // The cases that need a detector actually running — "turning it back on
    // starts monitoring again", "turning it off tears a running detector
    // down" — cannot be covered here: TripDetectionService.start() calls
    // Geolocator.getPositionStream directly rather than going through
    // LocationService, so there is no seam to fake and no platform channel on
    // the host. That is #82, and it is the reason auto-detection is the one
    // subsystem in the app with no scenario coverage either.
  });
}
