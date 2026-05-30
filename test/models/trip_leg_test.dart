import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/models/trip_leg.dart';

void main() {
  TripLeg sample() => TripLeg(
        id: 7,
        date: '2026-05-16',
        legOrder: 2,
        routeId: 3,
        startTime: DateTime(2026, 5, 16, 8, 15),
        endTime: DateTime(2026, 5, 16, 9, 30),
        startOdometer: 1000,
        endOdometer: 1054,
        startLocation: 'Koti',
        endLocation: 'Työ',
        routeDescription: 'Töihin',
        kmDriven: 54,
        purpose: 'Asiakas',
        driver: 'Lapa',
        kmAllowance: 30.78,
        dailyAllowance: 24.0,
        dailyAllowanceType: 1,
        isReturnHome: true,
        synced: true,
      );

  group('TripLeg serialization', () {
    test('toMap/fromMap round-trips, preserving dates', () {
      final restored = TripLeg.fromMap(sample().toMap());
      expect(restored.id, 7);
      expect(restored.date, '2026-05-16');
      expect(restored.startTime, DateTime(2026, 5, 16, 8, 15));
      expect(restored.endTime, DateTime(2026, 5, 16, 9, 30));
      expect(restored.endOdometer, 1054);
      expect(restored.kmAllowance, 30.78);
      expect(restored.dailyAllowanceType, 1);
      expect(restored.isReturnHome, true);
      expect(restored.synced, true);
    });

    test('handles null end time and end odometer', () {
      final open = TripLeg(
        date: '2026-05-16',
        legOrder: 1,
        startTime: DateTime(2026, 5, 16, 8, 0),
        startOdometer: 1000,
        startLocation: 'Koti',
        driver: 'Lapa',
      );
      final restored = TripLeg.fromMap(open.toMap());
      expect(restored.endTime, isNull);
      expect(restored.endOdometer, isNull);
      expect(restored.synced, false);
    });
  });

  group('copyWith', () {
    test('keeps dailyAllowanceType when not passed', () {
      expect(sample().copyWith().dailyAllowanceType, 1);
    });

    test('clears dailyAllowanceType when explicitly null', () {
      expect(sample().copyWith(dailyAllowanceType: null).dailyAllowanceType,
          isNull);
    });

    test('overrides only provided fields', () {
      final updated = sample().copyWith(kmDriven: 99);
      expect(updated.kmDriven, 99);
      expect(updated.driver, 'Lapa');
    });
  });

  test('totalAllowance is km plus daily allowance', () {
    expect(sample().totalAllowance, 30.78 + 24.0);
  });

  group('lifecycle predicates', () {
    TripLeg withEnd({int? endOdometer, String? endLocation}) => TripLeg(
          date: '2026-05-16',
          legOrder: 1,
          startTime: DateTime(2026, 5, 16, 8, 0),
          startOdometer: 1000,
          startLocation: 'Koti',
          driver: 'Lapa',
          endOdometer: endOdometer,
          endLocation: endLocation,
        );

    test('completed when both end odometer and end location are present', () {
      final l = withEnd(endOdometer: 1100, endLocation: 'Työ');
      expect(l.isCompleted, true);
      expect(l.isDraft, false);
    });

    test('draft when end odometer is missing', () {
      final l = withEnd(endLocation: 'Työ');
      expect(l.isCompleted, false);
      expect(l.isDraft, true);
    });

    test('draft when end location is empty', () {
      final l = withEnd(endOdometer: 1100, endLocation: '');
      expect(l.isCompleted, false);
      expect(l.isDraft, true);
    });

    test('isReturnHomeTo matches home trimmed and case-insensitively', () {
      final l = withEnd(endOdometer: 1100, endLocation: '  koti ');
      expect(l.isReturnHomeTo('Koti'), true);
      expect(l.isReturnHomeTo('  KOTI'), true);
    });

    test('isReturnHomeTo is false for a non-matching or null end location', () {
      expect(withEnd(endLocation: 'Työ').isReturnHomeTo('Koti'), false);
      expect(withEnd(endLocation: null).isReturnHomeTo('Koti'), false);
    });
  });
}
