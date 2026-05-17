import 'package:flutter_test/flutter_test.dart';

import 'package:kilometrikorvaus/models/app_settings.dart';
import 'package:kilometrikorvaus/models/route.dart';
import 'package:kilometrikorvaus/models/trip_leg.dart';
import 'package:kilometrikorvaus/models/km_rate.dart';
import 'package:kilometrikorvaus/services/trip_calculator.dart';
import 'package:kilometrikorvaus/services/csv_export_service.dart';
import 'package:kilometrikorvaus/models/expense.dart';
import 'package:kilometrikorvaus/models/location_zone.dart';

void main() {
  // ── AppSettings model tests ──

  group('AppSettings', () {
    test('default values', () {
      const settings = AppSettings();
      expect(settings.homeLocation, 'Koti');
      expect(settings.kmRate, 0.57);
      expect(settings.allowance6h, 25.0);
      expect(settings.allowance10h, 54.0);
      expect(settings.sheetId, '');
      expect(settings.sheetTab, 'Taulukko1');
    });

    test('toMap and fromMap round-trip', () {
      const settings = AppSettings(
        homeLocation: 'Helsinki',
        kmRate: 0.53,
        allowance6h: 20.0,
        allowance10h: 42.0,
        sheetId: 'abc123',
        sheetTab: 'Sheet1',
        driverName: 'Testi',
        debugLogging: true,
      );
      final map = settings.toMap();
      final restored = AppSettings.fromMap(map);

      expect(restored.homeLocation, 'Helsinki');
      expect(restored.kmRate, 0.53);
      expect(restored.allowance6h, 20.0);
      expect(restored.allowance10h, 42.0);
      expect(restored.sheetId, 'abc123');
      expect(restored.sheetTab, 'Sheet1');
      expect(restored.driverName, 'Testi');
      expect(restored.debugLogging, true);
    });

    test('copyWith preserves unchanged fields', () {
      const settings = AppSettings(
        homeLocation: 'Koti',
        kmRate: 0.57,
        allowance6h: 25.0,
      );
      final updated = settings.copyWith(homeLocation: 'Toimisto');
      expect(updated.homeLocation, 'Toimisto');
      expect(updated.kmRate, 0.57);
      expect(updated.allowance6h, 25.0);
    });

    test('fromMap handles empty map', () {
      final settings = AppSettings.fromMap({});
      expect(settings.homeLocation, 'Koti');
      expect(settings.kmRate, 0.57);
    });

    test('fromMap handles invalid numbers', () {
      final settings = AppSettings.fromMap({
        'km_rate': 'not-a-number',
        'allowance_6h': '',
      });
      expect(settings.kmRate, 0.57); // fallback to default
      expect(settings.allowance6h, 25.0);
    });
  });

  // ── Route model tests ──

  group('Route', () {
    final now = DateTime(2025, 5, 15, 10, 0);

    test('toMap and fromMap round-trip', () {
      final route = Route(
        id: 1,
        name: 'Test Route',
        startLocation: 'Start',
        endLocation: 'End',
        distanceKm: 54.5,
        lastPurpose: 'Meeting',
        createdAt: now,
        updatedAt: now,
      );
      final map = route.toMap();
      final restored = Route.fromMap(map);

      expect(restored.id, 1);
      expect(restored.name, 'Test Route');
      expect(restored.startLocation, 'Start');
      expect(restored.endLocation, 'End');
      expect(restored.distanceKm, 54.5);
      expect(restored.lastPurpose, 'Meeting');
    });

    test('toMap excludes null id for inserts', () {
      final route = Route(
        name: 'No ID',
        startLocation: 'A',
        endLocation: 'B',
        distanceKm: 10,
        createdAt: now,
        updatedAt: now,
      );
      final map = route.toMap();
      expect(map.containsKey('id'), false);
    });

    test('copyWith', () {
      final route = Route(
        id: 1,
        name: 'Original',
        startLocation: 'A',
        endLocation: 'B',
        distanceKm: 10,
        createdAt: now,
        updatedAt: now,
      );
      final updated = route.copyWith(name: 'Updated');
      expect(updated.name, 'Updated');
      expect(updated.id, 1);
      expect(updated.distanceKm, 10);
    });
  });

  // ── TripLeg model tests ──

  group('TripLeg', () {
    final now = DateTime(2025, 5, 15, 8, 0);

    test('toMap and fromMap round-trip', () {
      final leg = TripLeg(
        id: 1,
        date: '2025-05-15',
        legOrder: 1,
        routeId: 2,
        startTime: now,
        endTime: now.add(const Duration(hours: 1)),
        startOdometer: 10000,
        endOdometer: 10054,
        startLocation: 'Koti',
        endLocation: 'Työ',
        routeDescription: 'Koti → Työ',
        kmDriven: 54,
        workingTimeHours: 8,
        legDurationHours: 1,
        purpose: 'Työmatka',
        driver: 'Lapa',
        kmAllowance: 30.78,
        dailyAllowance: 25.0,
        dailyAllowanceType: 1,
        isReturnHome: false,
        synced: true,
      );
      final map = leg.toMap();
      final restored = TripLeg.fromMap(map);

      expect(restored.id, 1);
      expect(restored.date, '2025-05-15');
      expect(restored.legOrder, 1);
      expect(restored.routeId, 2);
      expect(restored.startOdometer, 10000);
      expect(restored.endOdometer, 10054);
      expect(restored.startLocation, 'Koti');
      expect(restored.endLocation, 'Työ');
      expect(restored.kmDriven, 54);
      expect(restored.kmAllowance, 30.78);
      expect(restored.dailyAllowance, 25.0);
      expect(restored.dailyAllowanceType, 1);
      expect(restored.isReturnHome, false);
      expect(restored.synced, true);
    });

    test('totalAllowance getter', () {
      final leg = TripLeg(
        date: '2025-05-15',
        legOrder: 1,
        startTime: now,
        startOdometer: 10000,
        startLocation: 'Koti',
        driver: 'Test',
        kmAllowance: 30.78,
        dailyAllowance: 25.0,
      );
      expect(leg.totalAllowance, 55.78);
    });

    test('copyWith with sentinel preserves dailyAllowanceType', () {
      final leg = TripLeg(
        date: '2025-05-15',
        legOrder: 1,
        startTime: now,
        startOdometer: 10000,
        startLocation: 'Koti',
        driver: 'Test',
        dailyAllowanceType: 2,
      );
      // copyWith without dailyAllowanceType should preserve it
      final updated = leg.copyWith(kmDriven: 54.0);
      expect(updated.dailyAllowanceType, 2);
      expect(updated.kmDriven, 54.0);
    });

    test('copyWith explicitly sets dailyAllowanceType to null', () {
      final leg = TripLeg(
        date: '2025-05-15',
        legOrder: 1,
        startTime: now,
        startOdometer: 10000,
        startLocation: 'Koti',
        driver: 'Test',
        dailyAllowanceType: 2,
      );
      final updated = leg.copyWith(dailyAllowanceType: null);
      expect(updated.dailyAllowanceType, null);
    });
  });

  // ── KmRate model tests ──

  group('KmRate', () {
    test('toMap and fromMap round-trip', () {
      final rate = KmRate(year: 2025, rate: 0.57);
      final map = rate.toMap();
      final restored = KmRate.fromMap(map);

      expect(restored.year, 2025);
      expect(restored.rate, 0.57);
    });

    test('copyWith', () {
      final rate = KmRate(year: 2025, rate: 0.57);
      final updated = rate.copyWith(rate: 0.60);

      expect(updated.year, 2025);
      expect(updated.rate, 0.60);
    });

    test('finnishDefaults contains known rates', () {
      expect(KmRate.finnishDefaults[2020], 0.43);
      expect(KmRate.finnishDefaults[2021], 0.44);
      expect(KmRate.finnishDefaults[2022], 0.46);
      expect(KmRate.finnishDefaults[2023], 0.53);
      expect(KmRate.finnishDefaults[2024], 0.57);
      expect(KmRate.finnishDefaults[2025], 0.57);
      expect(KmRate.finnishDefaults[2026], 0.55);
    });
  });

  // ── TripCalculator tests ──

  group('TripCalculator', () {
    final baseSettings = AppSettings(
      homeLocation: 'Koti',
      kmRate: 0.57,
      allowance6h: 25.0,
      allowance10h: 54.0,
    );

    final baseLeg = TripLeg(
      date: '2025-05-15',
      legOrder: 1,
      startTime: DateTime(2025, 5, 15, 8, 0),
      endTime: DateTime(2025, 5, 15, 9, 0),
      startOdometer: 10000,
      endOdometer: 10054,
      startLocation: 'Koti',
      endLocation: 'Työ',
      driver: 'Lapa',
    );

    // ── Leg calculation ──

    test('calculateLeg computes kmDriven from odometer delta', () {
      final calc = TripCalculator(baseSettings);
      final result = calc.calculateLeg(baseLeg);

      expect(result.kmDriven, 54);
      expect(result.kmAllowance, closeTo(30.78, 0.01));
    });

    test('calculateLeg detects return home', () {
      final calc = TripCalculator(baseSettings);
      final returnLeg = baseLeg.copyWith(endLocation: 'Koti');
      final result = calc.calculateLeg(returnLeg);

      expect(result.isReturnHome, true);
    });

    test('calculateLeg is not case-sensitive for home detection', () {
      final calc = TripCalculator(AppSettings(homeLocation: 'KOTI'));
      final leg = baseLeg.copyWith(endLocation: 'koti');
      final result = calc.calculateLeg(leg);

      expect(result.isReturnHome, true);
    });

    test('calculateLeg uses year-specific km rate', () {
      final calc = TripCalculator(
        baseSettings,
        kmRates: {2025: 0.53},
      );
      final result = calc.calculateLeg(baseLeg);

      // 54 km * 0.53 = 28.62
      expect(result.kmAllowance, closeTo(28.62, 0.01));
    });

    test('calculateLeg falls back to settings rate for unknown year', () {
      final calc = TripCalculator(
        baseSettings,
        kmRates: {2024: 0.46},
      );
      final result = calc.calculateLeg(baseLeg); // 2025 leg

      // Falls back to baseSettings.kmRate = 0.57
      expect(result.kmAllowance, closeTo(30.78, 0.01));
    });

    test('calculateLeg with different year uses correct rate', () {
      final calc = TripCalculator(
        AppSettings(kmRate: 0.57),
        kmRates: {2023: 0.53, 2025: 0.57},
      );
      final leg2023 = baseLeg.copyWith(date: '2023-06-15');
      final result = calc.calculateLeg(leg2023);

      expect(result.kmAllowance, closeTo(28.62, 0.01)); // 54 * 0.53
    });

    test('getKmRateForYear returns year-specific rate', () {
      final calc = TripCalculator(
        baseSettings,
        kmRates: {2023: 0.53},
      );
      expect(calc.getKmRateForYear(2023), 0.53);
      expect(calc.getKmRateForYear(2025), 0.57); // falls back to settings
    });

    test('calculateLeg handles null endOdometer gracefully', () {
      final calc = TripCalculator(baseSettings);
      // Construct directly with null endOdometer (copyWith can't unset it)
      final leg = TripLeg(
        date: '2025-05-15',
        legOrder: 1,
        startTime: DateTime(2025, 5, 15, 8, 0),
        startOdometer: 10000,
        endOdometer: null,
        startLocation: 'Koti',
        driver: 'Lapa',
      );
      final result = calc.calculateLeg(leg);

      expect(result.kmDriven, 0);
      expect(result.kmAllowance, 0);
    });

    // ── Daily allowance ──

    test('calculateDailyAllowance returns 0 for short trips (<6h)', () {
      final calc = TripCalculator(baseSettings);
      final legs = [
        TripLeg(
          date: '2025-05-15',
          legOrder: 1,
          startTime: DateTime(2025, 5, 15, 8, 0),
          endTime: DateTime(2025, 5, 15, 11, 0),
          startOdometer: 10000,
          endOdometer: 10054,
          startLocation: 'Koti',
          endLocation: 'Työ',
          driver: 'Lapa',
        ),
      ];

      final result = calc.calculateDailyAllowance(legs);
      expect(result.allowance, 0);
      expect(result.totalHours, closeTo(3.0, 0.01));
    });

    test('calculateDailyAllowance returns half allowance for 6-10h', () {
      final calc = TripCalculator(baseSettings);
      final legs = [
        TripLeg(
          date: '2025-05-15',
          legOrder: 1,
          startTime: DateTime(2025, 5, 15, 8, 0),
          endTime: DateTime(2025, 5, 15, 16, 0),
          startOdometer: 10000,
          endOdometer: 10054,
          startLocation: 'Koti',
          endLocation: 'Työ',
          driver: 'Lapa',
        ),
      ];

      final result = calc.calculateDailyAllowance(legs);
      expect(result.allowance, 25.0);
      expect(result.totalHours, closeTo(8.0, 0.01));
    });

    test('calculateDailyAllowance returns full allowance for >10h', () {
      final calc = TripCalculator(baseSettings);
      final legs = [
        TripLeg(
          date: '2025-05-15',
          legOrder: 1,
          startTime: DateTime(2025, 5, 15, 8, 0),
          endTime: DateTime(2025, 5, 15, 20, 0),
          startOdometer: 10000,
          endOdometer: 10054,
          startLocation: 'Koti',
          endLocation: 'Työ',
          driver: 'Lapa',
        ),
      ];

      final result = calc.calculateDailyAllowance(legs);
      expect(result.allowance, 54.0);
      expect(result.totalHours, closeTo(12.0, 0.01));
    });

    test('calculateDailyAllowance uses firstStart and lastEnd', () {
      final calc = TripCalculator(baseSettings);
      final legs = [
        TripLeg(
          date: '2025-05-15',
          legOrder: 1,
          startTime: DateTime(2025, 5, 15, 8, 0),
          endTime: DateTime(2025, 5, 15, 9, 0),
          startOdometer: 10000,
          endOdometer: 10054,
          startLocation: 'Koti',
          endLocation: 'Työ',
          driver: 'Lapa',
        ),
        TripLeg(
          date: '2025-05-15',
          legOrder: 2,
          startTime: DateTime(2025, 5, 15, 17, 0),
          endTime: DateTime(2025, 5, 15, 18, 0),
          startOdometer: 10054,
          endOdometer: 10108,
          startLocation: 'Työ',
          endLocation: 'Koti',
          driver: 'Lapa',
        ),
      ];

      final result = calc.calculateDailyAllowance(legs);
      // 8:00 to 18:00 = 10h → just at boundary, >10 is false, >6 is true
      expect(result.allowance, 25.0);
    });

    test('calculateDailyAllowance empty list', () {
      final calc = TripCalculator(baseSettings);
      final result = calc.calculateDailyAllowance([]);
      expect(result.allowance, 0);
      expect(result.totalHours, 0);
    });

    // ── Working times ──

    test('calculateWorkingTimes computes gaps between legs', () {
      final calc = TripCalculator(baseSettings);
      final legs = [
        TripLeg(
          date: '2025-05-15',
          legOrder: 1,
          startTime: DateTime(2025, 5, 15, 8, 0),
          endTime: DateTime(2025, 5, 15, 9, 0),
          startOdometer: 10000,
          endOdometer: 10054,
          startLocation: 'Koti',
          endLocation: 'Työ',
          driver: 'Lapa',
        ),
        TripLeg(
          date: '2025-05-15',
          legOrder: 2,
          startTime: DateTime(2025, 5, 15, 17, 0),
          endTime: DateTime(2025, 5, 15, 18, 0),
          startOdometer: 10054,
          endOdometer: 10108,
          startLocation: 'Työ',
          endLocation: 'Koti',
          driver: 'Lapa',
        ),
      ];

      final result = calc.calculateWorkingTimes(legs);

      // Leg 1: working time = 17:00 - 09:00 = 8h, but isReturnHome is true on second leg
      // Actually the first leg doesn't return home, so workingTime for leg 1 is 8h
      // Wait - leg 1 is not returning home. Leg 2 is returning home.
      // For leg 1: gap between leg1.end (9:00) and leg2.start (17:00) = 8h
      // For leg 2: isReturnHome = false in original leg... but we didn't set it.
      expect(result[0].workingTimeHours, 0); // stored on last leg
      expect(result[1].workingTimeHours, closeTo(8.0, 0.01)); // total on last
    });

    test('calculateWorkingTimes zero for return-home leg', () {
      final calc = TripCalculator(baseSettings);
      final legs = [
        TripLeg(
          date: '2025-05-15',
          legOrder: 1,
          startTime: DateTime(2025, 5, 15, 8, 0),
          endTime: DateTime(2025, 5, 15, 9, 0),
          startOdometer: 10000,
          endOdometer: 10054,
          startLocation: 'Koti',
          endLocation: 'Työ',
          driver: 'Lapa',
          isReturnHome: false,
        ),
        TripLeg(
          date: '2025-05-15',
          legOrder: 2,
          startTime: DateTime(2025, 5, 15, 17, 0),
          endTime: DateTime(2025, 5, 15, 18, 0),
          startOdometer: 10054,
          endOdometer: 10108,
          startLocation: 'Työ',
          endLocation: 'Koti',
          driver: 'Lapa',
          isReturnHome: true,
        ),
      ];

      final result = calc.calculateWorkingTimes(legs);

      // Total working time on last leg (index 1)
      // Leg 1: 17:00 - 09:00 = 8h, isReturnHome of leg 1 is false → 8h
      // Leg 2: isReturnHome of leg 2 is true → 0h for working time
      // Total = 8h on last leg
      expect(result[0].workingTimeHours, 0);
      expect(result[1].workingTimeHours, closeTo(8.0, 0.01));
    });

    test('calculateWorkingTimes empty list', () {
      final calc = TripCalculator(baseSettings);
      final result = calc.calculateWorkingTimes([]);
      expect(result, isEmpty);
    });

    test('calculateWorkingTimes single leg day', () {
      final calc = TripCalculator(baseSettings);
      final legs = [
        TripLeg(
          date: '2025-05-15',
          legOrder: 1,
          startTime: DateTime(2025, 5, 15, 8, 0),
          endTime: DateTime(2025, 5, 15, 9, 0),
          startOdometer: 10000,
          endOdometer: 10054,
          startLocation: 'Koti',
          endLocation: 'Työ',
          driver: 'Lapa',
        ),
      ];

      final result = calc.calculateWorkingTimes(legs);
      // Single leg, no next leg gap, no working time
      expect(result[0].workingTimeHours, 0);
    });

    // ── Day summary ──

    test('summarizeDay computes totals correctly', () {
      final calc = TripCalculator(baseSettings);
      final legs = [
        TripLeg(
          date: '2025-05-15',
          legOrder: 1,
          startTime: DateTime(2025, 5, 15, 8, 0),
          endTime: DateTime(2025, 5, 15, 9, 0),
          startOdometer: 10000,
          endOdometer: 10054,
          startLocation: 'Koti',
          endLocation: 'Työ',
          driver: 'Lapa',
          kmDriven: 54,
          kmAllowance: 30.78,
          dailyAllowance: 0,
        ),
        TripLeg(
          date: '2025-05-15',
          legOrder: 2,
          startTime: DateTime(2025, 5, 15, 17, 0),
          endTime: DateTime(2025, 5, 15, 18, 0),
          startOdometer: 10054,
          endOdometer: 10108,
          startLocation: 'Työ',
          endLocation: 'Koti',
          driver: 'Lapa',
          kmDriven: 54,
          kmAllowance: 30.78,
          dailyAllowance: 25.0,
        ),
      ];

      final summary = calc.summarizeDay(legs);
      expect(summary.totalKm, 108.0);
      expect(summary.totalKmAllowance, closeTo(61.56, 0.01));
      expect(summary.totalDailyAllowance, 25.0);
      expect(summary.grandTotal, closeTo(86.56, 0.01));
    });

    test('summarizeDay with empty list', () {
      final calc = TripCalculator(baseSettings);
      final summary = calc.summarizeDay([]);
      expect(summary.totalKm, 0);
      expect(summary.totalKmAllowance, 0);
      expect(summary.totalDailyAllowance, 0);
      expect(summary.grandTotal, 0);
    });
  });

  // ── LocationZone model tests ──

  group('LocationZone', () {
    test('toMap and fromMap round-trip', () {
      final zone = LocationZone(
        id: 1,
        name: 'Koti',
        latitude: 60.1699,
        longitude: 24.9384,
        radiusMeters: 200,
        createdAt: '2025-05-15T10:00:00',
      );
      final map = zone.toMap();
      final restored = LocationZone.fromMap(map);

      expect(restored.id, 1);
      expect(restored.name, 'Koti');
      expect(restored.latitude, 60.1699);
      expect(restored.longitude, 24.9384);
      expect(restored.radiusMeters, 200);
      expect(restored.createdAt, '2025-05-15T10:00:00');
    });

    test('toMap excludes null id for inserts', () {
      final zone = LocationZone(
        name: 'Toimisto',
        latitude: 60.2055,
        longitude: 24.6559,
        createdAt: '2025-05-15T10:00:00',
      );
      final map = zone.toMap();
      expect(map.containsKey('id'), false);
    });

    test('copyWith', () {
      final zone = LocationZone(
        id: 1,
        name: 'Koti',
        latitude: 60.1699,
        longitude: 24.9384,
        createdAt: '2025-05-15T10:00:00',
      );
      final updated = zone.copyWith(name: 'Uusi koti', radiusMeters: 500);
      expect(updated.name, 'Uusi koti');
      expect(updated.radiusMeters, 500);
      expect(updated.latitude, 60.1699);
      expect(updated.id, 1);
    });

    test('default radius is 200', () {
      final zone = LocationZone(
        name: 'Testi',
        latitude: 0,
        longitude: 0,
        createdAt: '2025-05-15T10:00:00',
      );
      expect(zone.radiusMeters, 200);
    });
  });

  // ── Expense model tests ──

  group('Expense', () {
    test('toMap and fromMap round-trip', () {
      final expense = Expense(
        id: 1,
        tripLegId: 42,
        type: ExpenseType.parking,
        amount: 5.50,
        description: 'Pysäköintitalo',
        createdAt: '2025-05-15T10:00:00',
      );
      final map = expense.toMap();
      final restored = Expense.fromMap(map);

      expect(restored.id, 1);
      expect(restored.tripLegId, 42);
      expect(restored.type, ExpenseType.parking);
      expect(restored.amount, 5.50);
      expect(restored.description, 'Pysäköintitalo');
      expect(restored.createdAt, '2025-05-15T10:00:00');
    });

    test('toMap excludes null id for inserts', () {
      final expense = Expense(
        type: ExpenseType.meal,
        amount: 12.90,
        createdAt: '2025-05-15T12:00:00',
      );
      final map = expense.toMap();
      expect(map.containsKey('id'), false);
    });

    test('copyWith', () {
      final expense = Expense(
        id: 1,
        tripLegId: 42,
        type: ExpenseType.toll,
        amount: 2.50,
        createdAt: '2025-05-15T10:00:00',
      );
      final updated = expense.copyWith(amount: 3.00, description: 'Silta');
      expect(updated.amount, 3.00);
      expect(updated.description, 'Silta');
      expect(updated.type, ExpenseType.toll);
      expect(updated.id, 1);
    });

    test('ExpenseType display names', () {
      expect(ExpenseType.parking.displayName, 'Pysäköinti');
      expect(ExpenseType.toll.displayName, 'Tietulli');
      expect(ExpenseType.meal.displayName, 'Ateria');
      expect(ExpenseType.other.displayName, 'Muu');
    });
  });

  // ── CsvExportService tests ──

  group('CsvExportService', () {
    final now = DateTime(2025, 5, 15, 8, 0);

    test('generateContent creates CSV with header and data rows', () {
      final legs = [
        TripLeg(
          id: 1,
          date: '2025-05-15',
          legOrder: 1,
          startTime: now,
          endTime: now.add(const Duration(hours: 1)),
          startOdometer: 10000,
          endOdometer: 10054,
          startLocation: 'Koti',
          endLocation: 'Työ',
          routeDescription: 'Koti → Työ',
          kmDriven: 54.0,
          purpose: 'Työmatka',
          driver: 'Lapa',
          kmAllowance: 30.78,
          dailyAllowance: 25.0,
          dailyAllowanceType: 1,
          isReturnHome: false,
        ),
      ];

      final content = CsvExportService.generateContent(legs);
      final lines = content.trim().split('\n');

      expect(lines.length, 2); // header + 1 data row
      expect(lines[0], contains('Päivämäärä'));
      expect(lines[0], contains('Km-korvaus (€)'));
      expect(lines[1], contains('2025-05-15'));
      expect(lines[1], contains('Koti'));
      expect(lines[1], contains('30.78'));
      expect(lines[1], contains('Puolipäivä'));
    });

    test('generateContent sorts legs by date and leg order', () {
      final legs = [
        TripLeg(
          id: 2,
          date: '2025-05-15',
          legOrder: 2,
          startTime: DateTime(2025, 5, 15, 17, 0),
          startOdometer: 10054,
          startLocation: 'Työ',
          driver: 'Lapa',
        ),
        TripLeg(
          id: 1,
          date: '2025-05-15',
          legOrder: 1,
          startTime: DateTime(2025, 5, 15, 8, 0),
          startOdometer: 10000,
          startLocation: 'Koti',
          driver: 'Lapa',
        ),
      ];

      final content = CsvExportService.generateContent(legs);
      final lines = content.trim().split('\n');

      expect(lines[1], contains('Koti'));
      expect(lines[2], contains('Työ'));
    });

    test('generateContent escapes CSV special characters', () {
      final legs = [
        TripLeg(
          id: 1,
          date: '2025-05-15',
          legOrder: 1,
          startTime: now,
          startOdometer: 10000,
          startLocation: 'Koti, Helsinki',
          purpose: 'Meeting "important"',
          driver: 'Lapa',
        ),
      ];

      final content = CsvExportService.generateContent(legs);

      expect(content, contains('"Koti, Helsinki"'));
      expect(content, contains('"Meeting ""important"""'));
    });

    test('generateContent includes expense rows', () {
      final legs = [
        TripLeg(
          id: 1,
          date: '2025-05-15',
          legOrder: 1,
          startTime: now,
          startOdometer: 10000,
          startLocation: 'Koti',
          driver: 'Lapa',
        ),
      ];

      final expenses = {
        1: [
          Expense(
            id: 1,
            tripLegId: 1,
            type: ExpenseType.parking,
            amount: 5.50,
            createdAt: '2025-05-15T10:00:00',
          ),
        ],
      };

      final content = CsvExportService.generateContent(legs, expensesByLegId: expenses);
      final lines = content.trim().split('\n');

      expect(lines.length, 3); // header + leg row + expense row
      expect(lines[1], contains('Matka'));
      expect(lines[2], contains('Kulu'));
      expect(lines[2], contains('Pysäköinti'));
      expect(lines[2], contains('5.50'));
    });
  });
}
