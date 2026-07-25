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

  // ── MovementSignal ─────────────────────────────────────────────────────
  //
  // The recency-based signal that gates the "Oletko perillä?" reminder. It
  // exists because the trip position stream is distance-filtered, so the
  // fixed-cadence counters of DrivingDetector above can't be driven from it.
  group('MovementSignal', () {
    final t0 = DateTime(2026, 5, 18, 8, 0, 0);
    MovementSignal signal() =>
        MovementSignal(recency: const Duration(minutes: 5));

    test('is not driving before any sample arrives', () {
      expect(signal().isDrivingAt(t0), isFalse);
    });

    test('a fix at driving speed means driving', () {
      final s = signal()..onSample(speedMps: 25.0, at: t0);
      expect(s.isDrivingAt(t0), isTrue);
    });

    test('a fix below the high-speed threshold does not', () {
      final s = signal()..onSample(speedMps: 4.9, at: t0);
      expect(s.isDrivingAt(t0), isFalse);
    });

    test('stays driving for the whole recency window', () {
      final s = signal()..onSample(speedMps: 25.0, at: t0);
      expect(s.isDrivingAt(t0.add(const Duration(minutes: 4, seconds: 59))),
          isTrue);
      expect(s.isDrivingAt(t0.add(const Duration(minutes: 5))), isFalse);
    });

    test('slow fixes after a fast one do not extend the window', () {
      final s = signal()..onSample(speedMps: 25.0, at: t0);
      s.onSample(speedMps: 0.0, at: t0.add(const Duration(minutes: 4)));
      expect(s.isDrivingAt(t0.add(const Duration(minutes: 6))), isFalse);
    });

    test('displacement rescues a fix whose reported speed is a bogus zero', () {
      // ~1.1 km of latitude in 30s ≈ 37 m/s. The fused provider does hand
      // back speed 0 on otherwise valid fixes; without this the reminder
      // would think a moving vehicle had stopped.
      final s = signal()
        ..onSample(speedMps: 0.0, at: t0, latitude: 60.0, longitude: 25.0)
        ..onSample(
          speedMps: 0.0,
          at: t0.add(const Duration(seconds: 30)),
          latitude: 60.01,
          longitude: 25.0,
        );
      expect(s.isDrivingAt(t0.add(const Duration(seconds: 30))), isTrue);
    });

    test('a stationary pair of fixes is not driving', () {
      final s = signal()
        ..onSample(speedMps: 0.0, at: t0, latitude: 60.0, longitude: 25.0)
        ..onSample(
          speedMps: 0.0,
          at: t0.add(const Duration(seconds: 30)),
          latitude: 60.0,
          longitude: 25.0,
        );
      expect(s.isDrivingAt(t0.add(const Duration(seconds: 30))), isFalse);
    });

    test('lastSampleAt separates "no GPS at all" from "GPS says stopped"', () {
      final s = signal();
      expect(s.lastSampleAt, isNull);
      s.onSample(speedMps: 0.0, at: t0);
      expect(s.lastSampleAt, t0);
    });

    test('reset forgets everything', () {
      final s = signal()..onSample(speedMps: 25.0, at: t0);
      s.reset();
      expect(s.isDrivingAt(t0), isFalse);
      expect(s.lastSampleAt, isNull);
    });
  });
}
