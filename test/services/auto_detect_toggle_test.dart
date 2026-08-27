import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/models/app_settings.dart';
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
