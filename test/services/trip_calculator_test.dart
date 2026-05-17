import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/models/app_settings.dart';
import 'package:kilometrikorvaus/models/trip_leg.dart';
import 'package:kilometrikorvaus/services/trip_calculator.dart';

TripLeg leg({
  DateTime? startTime,
  DateTime? endTime,
  int startOdometer = 1000,
  int? endOdometer,
  String? endLocation,
  int legOrder = 1,
  bool isReturnHome = false,
}) {
  return TripLeg(
    date: '2026-05-16',
    legOrder: legOrder,
    startTime: startTime ?? DateTime(2026, 5, 16, 8, 0),
    endTime: endTime,
    startOdometer: startOdometer,
    endOdometer: endOdometer,
    startLocation: 'Koti',
    endLocation: endLocation,
    driver: 'Lapa',
    isReturnHome: isReturnHome,
  );
}

void main() {
  final settings = AppSettings(
    homeLocation: 'Koti',
    kmRate: 0.57,
    allowance6h: 24.0,
    allowance10h: 48.0,
  );
  final calc = TripCalculator(settings);

  group('calculateLeg', () {
    test('km driven and allowance from odometer delta', () {
      final result =
          calc.calculateLeg(leg(startOdometer: 1000, endOdometer: 1100));
      expect(result.kmDriven, 100);
      expect(result.kmAllowance, 57.00);
    });

    test('rounds km allowance to 2 decimals', () {
      final result =
          calc.calculateLeg(leg(startOdometer: 1000, endOdometer: 1033));
      // 33 * 0.57 = 18.81
      expect(result.kmAllowance, 18.81);
    });

    test('same odometer reading yields zero km', () {
      final result =
          calc.calculateLeg(leg(startOdometer: 1000, endOdometer: 1000));
      expect(result.kmDriven, 0);
      expect(result.kmAllowance, 0);
    });

    test('missing end odometer yields zero km', () {
      final result = calc.calculateLeg(leg(startOdometer: 1000));
      expect(result.kmDriven, 0);
      expect(result.kmAllowance, 0);
    });

    test('detects return home (case-insensitive, trimmed)', () {
      expect(calc.calculateLeg(leg(endLocation: 'Koti')).isReturnHome, true);
      expect(calc.calculateLeg(leg(endLocation: '  koti ')).isReturnHome, true);
    });

    test('non-matching or null end location is not return home', () {
      expect(calc.calculateLeg(leg(endLocation: 'Työ')).isReturnHome, false);
      expect(calc.calculateLeg(leg(endLocation: null)).isReturnHome, false);
    });
  });

  group('calculateDailyAllowance', () {
    ({double allowance, double totalHours}) over(Duration d) {
      final start = DateTime(2026, 5, 16, 8, 0);
      return calc.calculateDailyAllowance([
        leg(legOrder: 1, startTime: start),
        leg(legOrder: 2, startTime: start, endTime: start.add(d)),
      ]);
    }

    test('empty list yields zero', () {
      final r = calc.calculateDailyAllowance([]);
      expect(r.allowance, 0);
      expect(r.totalHours, 0);
    });

    test('exactly 6h is below the 6h tier', () {
      expect(over(const Duration(hours: 6)).allowance, 0);
    });

    test('just over 6h yields 6h allowance', () {
      expect(over(const Duration(hours: 6, minutes: 1)).allowance, 24.0);
    });

    test('exactly 10h stays in the 6h tier', () {
      expect(over(const Duration(hours: 10)).allowance, 24.0);
    });

    test('just over 10h yields 10h allowance', () {
      expect(over(const Duration(hours: 10, minutes: 1)).allowance, 48.0);
    });

    test('falls back to last start time when end time missing', () {
      final start = DateTime(2026, 5, 16, 8, 0);
      final r = calc.calculateDailyAllowance([
        leg(legOrder: 1, startTime: start),
        leg(legOrder: 2, startTime: start.add(const Duration(hours: 7))),
      ]);
      expect(r.totalHours, 7.0);
      expect(r.allowance, 24.0);
    });
  });

  group('calculateWorkingTimes', () {
    test('gap between legs accumulates onto the last leg', () {
      final start = DateTime(2026, 5, 16, 8, 0);
      final legs = [
        leg(
          legOrder: 1,
          startTime: start,
          endTime: start.add(const Duration(hours: 1)),
        ),
        leg(
          legOrder: 2,
          startTime: start.add(const Duration(hours: 1, minutes: 30)),
          endTime: start.add(const Duration(hours: 2)),
        ),
      ];
      final result = calc.calculateWorkingTimes(legs);
      expect(result.first.workingTimeHours, 0);
      expect(result.last.workingTimeHours, 0.5);
    });

    test('working time spans first arrival to last departure', () {
      final start = DateTime(2026, 5, 16, 8, 0);
      final legs = [
        leg(
          legOrder: 1,
          startTime: start,
          endTime: start.add(const Duration(hours: 1)),
          isReturnHome: true,
        ),
        leg(
          legOrder: 2,
          startTime: start.add(const Duration(hours: 3)),
          endTime: start.add(const Duration(hours: 4)),
        ),
      ];
      final result = calc.calculateWorkingTimes(legs);
      // PR #36 definition: lastStart (11:00) - firstEnd (09:00) = 2.0h.
      // The return-home flag does not reduce working time.
      expect(result.last.workingTimeHours, 2.0);
    });

    test('single leg has zero working time', () {
      final result = calc.calculateWorkingTimes([leg()]);
      expect(result.single.workingTimeHours, 0);
    });
  });

  group('summarizeDay', () {
    test('folds km and allowance totals', () {
      final legs = [
        leg().copyWith(kmDriven: 50, kmAllowance: 28.50, dailyAllowance: 0),
        leg().copyWith(kmDriven: 50, kmAllowance: 28.50, dailyAllowance: 24.0),
      ];
      final s = calc.summarizeDay(legs);
      expect(s.totalKm, 100);
      expect(s.totalKmAllowance, 57.0);
      expect(s.totalDailyAllowance, 24.0);
      expect(s.grandTotal, 81.0);
    });

    test('empty day sums to zero', () {
      final s = calc.summarizeDay([]);
      expect(s.totalKm, 0);
      expect(s.totalKmAllowance, 0);
      expect(s.totalDailyAllowance, 0);
      expect(s.grandTotal, 0);
    });
  });
}
