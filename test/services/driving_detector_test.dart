import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/services/driving_detector.dart';

void main() {
  // Default config: highSpeed 5, lowSpeed 1, driving after 30s, arrived after
  // 60s, 10s per sample/tick.
  DrivingDetector detector() => DrivingDetector();

  // Feed [count] samples at [speed], ticking after each (mimics the adapter).
  DetectionEvent? drive(DrivingDetector d, double speed, int count) {
    DetectionEvent? last;
    for (var i = 0; i < count; i++) {
      d.onSample(speed);
      final e = d.tick();
      if (e != null) last = e;
    }
    return last;
  }

  group('startMonitoring', () {
    test('moves idle to monitoring', () {
      final d = detector()..startMonitoring();
      expect(d.state, DetectionState.monitoring);
    });
  });

  group('driving detection', () {
    test('fires after 30s of fast movement', () {
      final d = detector()..startMonitoring();
      // 2 fast samples = 20s: not yet.
      expect(drive(d, 10, 2), isNull);
      expect(d.state, DetectionState.monitoring);
      // 3rd fast sample crosses 30s.
      d.onSample(10);
      expect(d.tick(), DetectionEvent.drivingDetected);
      expect(d.state, DetectionState.driving);
    });

    test('does not fire while merely monitoring slow movement', () {
      final d = detector()..startMonitoring();
      expect(drive(d, 3, 10), isNull); // 1-5 m/s never accrues fast time
      expect(d.state, DetectionState.monitoring);
    });

    test('fast-movement time accumulates across a brief slowdown', () {
      // Legacy behaviour: while monitoring, a non-fast sample clears only the
      // stop counter, never the accrued fast-movement time.
      final d = detector()..startMonitoring();
      drive(d, 10, 2); // 20s fast
      d.onSample(2); // 1-5 m/s sample does not reset the fast counter
      d.tick();
      d.onSample(10); // one more fast sample -> 30s total
      expect(d.tick(), DetectionEvent.drivingDetected);
    });
  });

  group('arrival detection', () {
    DrivingDetector driving() {
      final d = detector()..startMonitoring();
      drive(d, 10, 3); // -> driving
      assert(d.state == DetectionState.driving);
      return d;
    }

    test('fires after 60s stopped once driving was observed', () {
      final d = driving();
      // 5 stopped samples = 50s: not yet.
      expect(drive(d, 0, 5), isNull);
      expect(d.state, DetectionState.driving);
      // 6th stopped sample crosses 60s.
      d.onSample(0);
      expect(d.tick(), DetectionEvent.arrivedDetected);
      expect(d.state, DetectionState.arrived);
    });

    test('a brief stop under 60s does not trigger arrival', () {
      final d = driving();
      expect(drive(d, 0, 5), isNull); // 50s stopped
      drive(d, 10, 1); // moving again resets the stop counter
      expect(drive(d, 0, 5), isNull); // another 50s -> still not arrived
      expect(d.state, DetectionState.driving);
    });
  });

  group('markTripStarted (manual start)', () {
    test('enters driving but will not auto-detect arrival without real driving',
        () {
      // Mirrors the legacy resetAfterTripStart: _wasDriving stays false, so a
      // hand-started trip that never sees fast movement won't fire arrival.
      final d = detector()..markTripStarted();
      expect(d.state, DetectionState.driving);
      expect(drive(d, 0, 10), isNull); // 100s stopped, but never drove
      expect(d.state, DetectionState.driving);
    });

    test('arrival stays disabled even after fast movement (legacy quirk: the '
        'wasDriving latch only sets via the monitoring path)', () {
      final d = detector()..markTripStarted();
      drive(d, 10, 5); // fast movement, but already forced into driving state
      expect(drive(d, 0, 6), isNull); // 60s stopped -> still no arrival
      expect(d.state, DetectionState.driving);
    });
  });

  group('reset', () {
    test('returns to idle', () {
      final d = detector()..startMonitoring();
      drive(d, 10, 3);
      d.reset();
      expect(d.state, DetectionState.idle);
    });
  });

  group('configurable thresholds', () {
    test('a tighter config detects driving sooner', () {
      final d = DrivingDetector(
        config: const DetectionConfig(drivingAfterSeconds: 10),
      )..startMonitoring();
      d.onSample(10);
      expect(d.tick(), DetectionEvent.drivingDetected); // one 10s sample
    });
  });
}
