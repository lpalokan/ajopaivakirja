import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/services/travel_day.dart';

/// Monday 2026-05-18 08:00 — every case departs from here so the expected
/// travel-day boundaries are easy to read: 08:00 on each following day.
final _departure = DateTime(2026, 5, 18, 8, 0);

List<TravelDay> _after(Duration trip) =>
    travelDaysFor(_departure, _departure.add(trip));

List<AllowanceType> _types(Duration trip) =>
    _after(trip).map((d) => d.type).toList();

void main() {
  group('inside a single travel day', () {
    test('under 6 hours earns nothing', () {
      expect(_after(const Duration(hours: 5, minutes: 59)), isEmpty);
    });

    test('exactly 6 hours earns nothing — the rule says "over"', () {
      expect(_after(const Duration(hours: 6)), isEmpty);
    });

    test('over 6 hours earns a half allowance', () {
      expect(_types(const Duration(hours: 6, minutes: 1)), [
        AllowanceType.half,
      ]);
    });

    test('exactly 10 hours is still only half', () {
      expect(_types(const Duration(hours: 10)), [AllowanceType.half]);
    });

    test('over 10 hours earns a full allowance', () {
      expect(_types(const Duration(hours: 10, minutes: 1)), [
        AllowanceType.full,
      ]);
    });
  });

  group('trips longer than one travel day', () {
    test('a complete travel day earns a full allowance and nothing more', () {
      expect(_types(const Duration(hours: 24)), [AllowanceType.full]);
    });

    test('remainder of 2 hours or less adds nothing', () {
      expect(_types(const Duration(hours: 26)), [AllowanceType.full]);
    });

    test('remainder over 2 hours adds a half allowance', () {
      expect(_types(const Duration(hours: 26, minutes: 1)), [
        AllowanceType.full,
        AllowanceType.half,
      ]);
    });

    test('remainder over 6 hours adds a full allowance', () {
      expect(_types(const Duration(hours: 30, minutes: 1)), [
        AllowanceType.full,
        AllowanceType.full,
      ]);
    });

    test(
      'the reported two-day trip: out Monday morning, home Tuesday afternoon',
      () {
        // 08:00 Monday → 16:00 Tuesday is 32 hours: one complete travel day
        // plus an 8-hour remainder. Both earn the full rate. The app used to
        // pay nothing for either day, because neither calendar date on its
        // own looks like more than a few hours of driving.
        final days = travelDaysFor(_departure, DateTime(2026, 5, 19, 16, 0));

        expect(days.map((d) => d.type), [
          AllowanceType.full,
          AllowanceType.full,
        ]);
        expect(days.map((d) => d.date), ['2026-05-18', '2026-05-19']);
      },
    );

    test('a three-day trip pays for the day nobody drove', () {
      // Out Monday 08:00, back Wednesday 18:00 = 58 hours. The middle
      // travel day starts Tuesday, a date with no legs at all — which is
      // why allowances cannot live on legs.
      final days = travelDaysFor(_departure, DateTime(2026, 5, 20, 18, 0));

      expect(days, hasLength(3));
      expect(days.map((d) => d.date), [
        '2026-05-18',
        '2026-05-19',
        '2026-05-20',
      ]);
      expect(days.every((d) => d.type == AllowanceType.full), isTrue);
    });

    test('each complete travel day starts 24 hours after the previous', () {
      final days = travelDaysFor(_departure, DateTime(2026, 5, 21, 9, 0));

      expect(days.map((d) => d.start), [
        DateTime(2026, 5, 18, 8, 0),
        DateTime(2026, 5, 19, 8, 0),
        DateTime(2026, 5, 20, 8, 0),
      ]);
      // 73 hours total: 3 complete days + 1 hour, which earns nothing.
      expect(days, hasLength(3));
    });
  });

  group('degenerate input', () {
    test('a return before the departure earns nothing', () {
      expect(
        travelDaysFor(
          _departure,
          _departure.subtract(const Duration(hours: 1)),
        ),
        isEmpty,
      );
    });

    test('a zero-length trip earns nothing', () {
      expect(travelDaysFor(_departure, _departure), isEmpty);
    });
  });
}
