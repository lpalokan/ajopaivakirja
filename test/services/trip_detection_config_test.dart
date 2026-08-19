import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/models/app_settings.dart';
import 'package:kilometrikorvaus/services/trip_detection_service.dart';

void main() {
  group('detectionConfigFrom', () {
    test('carries the user thresholds into the detector config', () {
      const settings = AppSettings(
        detectionSpeedMps: 7.0,
        detectionDrivingSeconds: 90,
        detectionArrivalSeconds: 150,
      );

      final config = TripDetectionService.detectionConfigFrom(settings);

      expect(config.highSpeed, 7.0);
      expect(config.drivingAfterSeconds, 90);
      expect(config.arrivedAfterSeconds, 150);
    });

    test('defaults reproduce the previously hard-coded thresholds', () {
      final config = TripDetectionService.detectionConfigFrom(
        const AppSettings(),
      );

      expect(config.highSpeed, 5.0);
      expect(config.drivingAfterSeconds, 30);
      expect(config.arrivedAfterSeconds, 60);
      // Not user-tunable: the sampling cadence is a property of the feed.
      expect(config.sampleIntervalSeconds, 10);
      expect(config.lowSpeed, 1.0);
    });

    test('clamps values that a stale row or a newer build could hold', () {
      final config = TripDetectionService.detectionConfigFrom(
        const AppSettings(
          detectionSpeedMps: 100.0,
          detectionDrivingSeconds: 0,
          detectionArrivalSeconds: 10000,
        ),
      );

      expect(config.highSpeed, AppSettings.maxDetectionSpeedMps);
      expect(
        config.drivingAfterSeconds,
        AppSettings.minDetectionDrivingSeconds,
      );
      expect(
        config.arrivedAfterSeconds,
        AppSettings.maxDetectionArrivalSeconds,
      );
    });
  });
}
