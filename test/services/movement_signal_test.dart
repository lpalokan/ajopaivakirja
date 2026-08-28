import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/services/movement_signal.dart';

/// MovementSignal outlived the auto-detection it was extracted alongside: it
/// is what gates the "Oletko perillä?" reminder while a trip is running, and
/// it is the only thing that can tell a parked vehicle from a vehicle whose
/// GPS has simply gone quiet.
void main() {
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
      expect(
        s.isDrivingAt(t0.add(const Duration(minutes: 4, seconds: 59))),
        isTrue,
      );
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
