import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/models/app_settings.dart';
import 'package:kilometrikorvaus/models/trip_leg.dart';
import 'package:kilometrikorvaus/services/trip_calculator.dart';

TripLeg _leg({
  required int id,
  required String date,
  required DateTime start,
  DateTime? end,
  String from = 'Koti',
  String? to = 'Työ',
  int legOrder = 1,
  int? allowanceType,
}) => TripLeg(
  id: id,
  date: date,
  legOrder: legOrder,
  startTime: start,
  endTime: end,
  startOdometer: 1000,
  endOdometer: 1054,
  startLocation: from,
  endLocation: to,
  driver: 'Lapa',
  dailyAllowanceType: allowanceType,
);

void main() {
  const settings = AppSettings(
    homeLocation: 'Koti',
    allowance6h: 25.0,
    allowance10h: 54.0,
  );
  final calc = TripCalculator(settings);

  group('tripLegsEndingWith', () {
    test('gathers an overnight trip across two dates', () {
      final out = _leg(
        id: 1,
        date: '2026-05-18',
        start: DateTime(2026, 5, 18, 8, 0),
        end: DateTime(2026, 5, 18, 11, 0),
      );
      final back = _leg(
        id: 2,
        date: '2026-05-19',
        start: DateTime(2026, 5, 19, 13, 0),
        end: DateTime(2026, 5, 19, 16, 0),
        from: 'Työ',
        to: 'Koti',
      );

      final trip = TripCalculator.tripLegsEndingWith([out, back], back, 'Koti');

      expect(
        trip.map((l) => l.id),
        [1, 2],
        reason:
            'the trip is what earns päivärahat; finalizing only the return '
            "date sees a two-hour drive and pays nothing",
      );
    });

    test('stops at the departure from home, excluding an earlier trip', () {
      final earlier = _leg(
        id: 1,
        date: '2026-05-10',
        start: DateTime(2026, 5, 10, 8, 0),
        end: DateTime(2026, 5, 10, 9, 0),
        to: 'Koti',
      );
      final out = _leg(
        id: 2,
        date: '2026-05-18',
        start: DateTime(2026, 5, 18, 8, 0),
        end: DateTime(2026, 5, 18, 11, 0),
      );
      final back = _leg(
        id: 3,
        date: '2026-05-19',
        start: DateTime(2026, 5, 19, 13, 0),
        end: DateTime(2026, 5, 19, 16, 0),
        from: 'Työ',
        to: 'Koti',
      );

      final trip = TripCalculator.tripLegsEndingWith(
        [earlier, out, back],
        back,
        'Koti',
      );

      expect(trip.map((l) => l.id), [2, 3]);
    });

    test('a same-day out-and-back is one trip', () {
      final out = _leg(
        id: 1,
        date: '2026-05-18',
        start: DateTime(2026, 5, 18, 8, 0),
        end: DateTime(2026, 5, 18, 9, 0),
      );
      final back = _leg(
        id: 2,
        date: '2026-05-18',
        legOrder: 2,
        start: DateTime(2026, 5, 18, 17, 0),
        end: DateTime(2026, 5, 18, 18, 0),
        from: 'Työ',
        to: 'Koti',
      );

      expect(
        TripCalculator.tripLegsEndingWith([out, back], back, 'Koti').length,
        2,
      );
    });

    test('a gap of over a week breaks the chain', () {
      // No leg departs from home, so without the gap rule this would drag
      // unrelated history into one enormous "trip".
      final stray = _leg(
        id: 1,
        date: '2026-04-01',
        start: DateTime(2026, 4, 1, 8, 0),
        end: DateTime(2026, 4, 1, 9, 0),
        from: 'Varasto',
        to: 'Asiakas',
      );
      final back = _leg(
        id: 2,
        date: '2026-05-19',
        start: DateTime(2026, 5, 19, 13, 0),
        end: DateTime(2026, 5, 19, 16, 0),
        from: 'Työ',
        to: 'Koti',
      );

      expect(
        TripCalculator.tripLegsEndingWith(
          [stray, back],
          back,
          'Koti',
        ).map((l) => l.id),
        [2],
      );
    });
  });

  group('allowancesForTrip', () {
    test('the reported overnight trip pays two full päivärahat', () {
      final trip = [
        _leg(
          id: 1,
          date: '2026-05-18',
          start: DateTime(2026, 5, 18, 8, 0),
          end: DateTime(2026, 5, 18, 11, 0),
        ),
        _leg(
          id: 2,
          date: '2026-05-19',
          start: DateTime(2026, 5, 19, 13, 0),
          end: DateTime(2026, 5, 19, 16, 0),
          from: 'Työ',
          to: 'Koti',
        ),
      ];

      final allowances = calc.allowancesForTrip(trip);

      expect(allowances.map((a) => a.date), ['2026-05-18', '2026-05-19']);
      expect(allowances.every((a) => a.isFull), isTrue);
      expect(allowances.fold<double>(0, (s, a) => s + a.amount), 108.0);
    });

    test('one allowance per travel day, keyed by its own period', () {
      final trip = [
        _leg(
          id: 1,
          date: '2026-05-18',
          start: DateTime(2026, 5, 18, 8, 0),
          end: DateTime(2026, 5, 18, 11, 0),
        ),
        _leg(
          id: 2,
          date: '2026-05-20',
          start: DateTime(2026, 5, 20, 15, 0),
          end: DateTime(2026, 5, 20, 18, 0),
          from: 'Työ',
          to: 'Koti',
        ),
      ];

      final allowances = calc.allowancesForTrip(trip);

      // Monday 08:00 → Wednesday 18:00 = 58 h: two complete travel days plus
      // a 10-hour remainder. The middle one falls on a date with no legs.
      expect(allowances.map((a) => a.date), [
        '2026-05-18',
        '2026-05-19',
        '2026-05-20',
      ]);
      expect(allowances.map((a) => a.periodStart), [
        '2026-05-18T08:00:00.000',
        '2026-05-19T08:00:00.000',
        '2026-05-20T08:00:00.000',
      ]);
    });

    test('a manual override wins for the day it is set on', () {
      final trip = [
        _leg(
          id: 1,
          date: '2026-05-18',
          start: DateTime(2026, 5, 18, 8, 0),
          end: DateTime(2026, 5, 18, 11, 0),
          allowanceType: 1,
        ),
        _leg(
          id: 2,
          date: '2026-05-19',
          start: DateTime(2026, 5, 19, 13, 0),
          end: DateTime(2026, 5, 19, 16, 0),
          from: 'Työ',
          to: 'Koti',
        ),
      ];

      final allowances = calc.allowancesForTrip(trip);

      expect(allowances.first.isHalf, isTrue);
      expect(allowances.first.amount, 25.0);
      expect(allowances.last.isFull, isTrue);
    });

    test('an unfinished trip has earned nothing yet', () {
      final trip = [
        _leg(
          id: 1,
          date: '2026-05-18',
          start: DateTime(2026, 5, 18, 8, 0),
          end: null,
        ),
      ];

      expect(calc.allowancesForTrip(trip), isEmpty);
    });

    test('no legs, no allowances', () {
      expect(calc.allowancesForTrip([]), isEmpty);
    });
  });
}
