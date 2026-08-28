import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/models/daily_allowance.dart';
import 'package:kilometrikorvaus/models/trip_leg.dart';
import 'package:kilometrikorvaus/services/allowance_ledger.dart';

DailyAllowance allowance(
  String date, {
  int type = 2,
  double amount = 54.0,
  String? periodStart,
}) => DailyAllowance(
  date: date,
  periodStart: periodStart ?? '${date}T08:00:00.000',
  type: type,
  amount: amount,
  createdAt: '${date}T20:00:00.000',
);

TripLeg leg(String date, int order) => TripLeg(
  id: int.parse(date.replaceAll('-', '')) + order,
  date: date,
  legOrder: order,
  startTime: DateTime.parse('${date}T08:00:00'),
  endTime: DateTime.parse('${date}T09:00:00'),
  startOdometer: 1000 * order,
  endOdometer: 1000 * order + 54,
  startLocation: 'Koti',
  endLocation: 'Työ',
  driver: 'Lapa',
);

void main() {
  group('totals', () {
    test('a date with no allowance pays nothing', () {
      expect(AllowanceLedger.empty.totalFor('2026-05-15'), 0);
      expect(AllowanceLedger.empty.total, 0);
    });

    test('sums the whole ledger and each of its dates', () {
      final ledger = AllowanceLedger([
        allowance('2026-05-15'),
        allowance('2026-05-16', type: 1, amount: 25.0),
      ]);

      expect(ledger.totalFor('2026-05-15'), 54.0);
      expect(ledger.totalFor('2026-05-16'), 25.0);
      expect(ledger.total, 79.0);
      expect(ledger.dates, ['2026-05-15', '2026-05-16']);
    });
  });

  group('placement on a day\'s legs', () {
    test('the whole day goes on the last leg', () {
      // The reports have always shown one päiväraha figure per day, at the
      // end of the day. Spreading it would change every column total.
      final ledger = AllowanceLedger([allowance('2026-05-15')]);
      final legs = [leg('2026-05-15', 1), leg('2026-05-15', 2)];

      expect(ledger.forLeg(legs[0], legs), 0);
      expect(ledger.forLeg(legs[1], legs), 54.0);
    });

    test('a single leg carries the day on its own', () {
      final ledger = AllowanceLedger([allowance('2026-05-15')]);
      final legs = [leg('2026-05-15', 1)];

      expect(ledger.forLeg(legs.single, legs), 54.0);
    });

    test('a day that earned nothing puts nothing anywhere', () {
      final legs = [leg('2026-05-15', 1)];

      expect(AllowanceLedger.empty.forLeg(legs.single, legs), 0);
    });

    test('a day\'s figure is never counted twice across its legs', () {
      final ledger = AllowanceLedger([allowance('2026-05-15')]);
      final legs = [
        leg('2026-05-15', 1),
        leg('2026-05-15', 2),
        leg('2026-05-15', 3),
      ];

      final sum = legs.fold<double>(0, (s, l) => s + ledger.forLeg(l, legs));
      expect(sum, ledger.totalFor('2026-05-15'));
    });
  });

  group('travel days with no driving', () {
    test('finds the middle day of a three-day trip', () {
      // The bug this class exists for: day two is a travel day, earns a full
      // kokopäiväraha, and has no leg for a report to hang it on.
      final ledger = AllowanceLedger([
        allowance('2026-05-15'),
        allowance('2026-05-16'),
        allowance('2026-05-17', type: 1, amount: 25.0),
      ]);

      expect(ledger.orphanDates(['2026-05-15', '2026-05-17']), ['2026-05-16']);
    });

    test('a date with legs is never an orphan', () {
      final ledger = AllowanceLedger([allowance('2026-05-15')]);

      expect(ledger.orphanDates(['2026-05-15']), isEmpty);
    });

    test('a date that earned nothing is not reported as a missing day', () {
      final ledger = AllowanceLedger([allowance('2026-05-16', amount: 0)]);

      expect(ledger.orphanDates(const []), isEmpty);
    });
  });

  group('describing a day', () {
    test('names a full and a half day', () {
      final ledger = AllowanceLedger([
        allowance('2026-05-15'),
        allowance('2026-05-16', type: 1, amount: 25.0),
      ]);

      expect(ledger.describe('2026-05-15'), 'Kokopäiväraha');
      expect(ledger.describe('2026-05-16'), 'Osapäiväraha');
      expect(ledger.typeFor('2026-05-15'), 2);
      expect(ledger.typeFor('2026-05-16'), 1);
    });

    test('counts two travel days landing on one date', () {
      final ledger = AllowanceLedger([
        allowance('2026-05-15', periodStart: '2026-05-15T02:00:00.000'),
        allowance('2026-05-15', periodStart: '2026-05-15T23:00:00.000'),
      ]);

      expect(ledger.describe('2026-05-15'), '2 × kokopäiväraha');
      expect(ledger.totalFor('2026-05-15'), 108.0);
      expect(ledger.typeFor('2026-05-15'), 2);
    });

    test('spells out a date that mixes a full and a half day', () {
      final ledger = AllowanceLedger([
        allowance('2026-05-15', periodStart: '2026-05-15T02:00:00.000'),
        allowance(
          '2026-05-15',
          type: 1,
          amount: 25.0,
          periodStart: '2026-05-15T23:00:00.000',
        ),
      ]);

      expect(
        ledger.describe('2026-05-15'),
        '1 × kokopäiväraha, 1 × osapäiväraha',
      );
      // Two different types cannot be named by one label.
      expect(ledger.typeFor('2026-05-15'), isNull);
    });

    test('says nothing about a date that earned nothing', () {
      expect(AllowanceLedger.empty.describe('2026-05-15'), isNull);
      expect(AllowanceLedger.empty.typeFor('2026-05-15'), isNull);
    });
  });
}
