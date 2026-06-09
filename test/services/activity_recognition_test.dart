import 'package:flutter_activity_recognition/flutter_activity_recognition.dart'
    as plugin;
import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/services/activity_recognition_service.dart';

void main() {
  group('mapActivity confidence gating', () {
    test('HIGH-confidence in_vehicle maps to inVehicle', () {
      expect(
        mapActivity(
          plugin.ActivityType.IN_VEHICLE,
          plugin.ActivityConfidence.HIGH,
        ),
        DrivingActivity.inVehicle,
      );
    });

    test('MEDIUM-confidence still maps through', () {
      expect(
        mapActivity(
          plugin.ActivityType.STILL,
          plugin.ActivityConfidence.MEDIUM,
        ),
        DrivingActivity.still,
      );
    });

    test('LOW-confidence readings are dropped (null) regardless of type', () {
      // A spurious low-confidence still/unknown must not clobber the last
      // confident in_vehicle reading mid-drive.
      expect(
        mapActivity(plugin.ActivityType.STILL, plugin.ActivityConfidence.LOW),
        isNull,
      );
      expect(
        mapActivity(
          plugin.ActivityType.UNKNOWN,
          plugin.ActivityConfidence.LOW,
        ),
        isNull,
      );
      expect(
        mapActivity(
          plugin.ActivityType.IN_VEHICLE,
          plugin.ActivityConfidence.LOW,
        ),
        isNull,
      );
    });

    test('every non-low activity type maps to its enum', () {
      const cases = {
        plugin.ActivityType.IN_VEHICLE: DrivingActivity.inVehicle,
        plugin.ActivityType.ON_BICYCLE: DrivingActivity.onBicycle,
        plugin.ActivityType.WALKING: DrivingActivity.walking,
        plugin.ActivityType.RUNNING: DrivingActivity.running,
        plugin.ActivityType.STILL: DrivingActivity.still,
        plugin.ActivityType.UNKNOWN: DrivingActivity.unknown,
      };
      cases.forEach((type, expected) {
        expect(
          mapActivity(type, plugin.ActivityConfidence.HIGH),
          expected,
        );
      });
    });
  });
}
