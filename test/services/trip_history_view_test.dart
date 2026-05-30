import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/models/trip_leg.dart';
import 'package:kilometrikorvaus/services/trip_history_view.dart';

TripLeg leg({
  required String date,
  int legOrder = 1,
  int? endOdometer = 1100,
  String? endLocation = 'Työ',
  bool synced = true,
}) {
  return TripLeg(
    date: date,
    legOrder: legOrder,
    startTime: DateTime(2026, 5, 16, 8, 0),
    startOdometer: 1000,
    endOdometer: endOdometer,
    startLocation: 'Koti',
    endLocation: endLocation,
    driver: 'Lapa',
    synced: synced,
  );
}

void main() {
  group('hasUnsynced', () {
    test('false when every leg is synced', () {
      expect(
        TripHistoryView.hasUnsynced({
          '2026-05-16': [leg(date: '2026-05-16')],
        }),
        false,
      );
    });

    test('true when any leg on any day is unsynced', () {
      expect(
        TripHistoryView.hasUnsynced({
          '2026-05-16': [leg(date: '2026-05-16')],
          '2026-05-15': [leg(date: '2026-05-15', synced: false)],
        }),
        true,
      );
    });

    test('false for no data', () {
      expect(TripHistoryView.hasUnsynced({}), false);
    });
  });

  group('monthNameFi', () {
    test('maps month numbers to Finnish names', () {
      expect(TripHistoryView.monthNameFi(5), 'Toukokuu');
      expect(TripHistoryView.monthNameFi(12), 'Joulukuu');
    });

    test('out-of-range month is empty', () {
      expect(TripHistoryView.monthNameFi(0), '');
      expect(TripHistoryView.monthNameFi(13), '');
    });
  });

  group('completeMonthName', () {
    test('null while any draft exists', () {
      expect(
        TripHistoryView.completeMonthName(
          dates: ['2026-05-16'],
          legsByDate: {
            '2026-05-16': [leg(date: '2026-05-16')],
          },
          draftCount: 1,
        ),
        isNull,
      );
    });

    test('names the most recent fully completed and synced month', () {
      final dates = ['2026-05-16', '2026-04-10'];
      final result = TripHistoryView.completeMonthName(
        dates: dates,
        legsByDate: {
          '2026-05-16': [leg(date: '2026-05-16')],
          '2026-04-10': [leg(date: '2026-04-10')],
        },
        draftCount: 0,
      );
      expect(result, 'Toukokuu'); // first (most recent) qualifying date wins
    });

    test('skips a day with an unsynced leg and falls to an earlier month', () {
      final dates = ['2026-05-16', '2026-04-10'];
      final result = TripHistoryView.completeMonthName(
        dates: dates,
        legsByDate: {
          '2026-05-16': [leg(date: '2026-05-16', synced: false)],
          '2026-04-10': [leg(date: '2026-04-10')],
        },
        draftCount: 0,
      );
      expect(result, 'Huhtikuu');
    });

    test('null when no day fully qualifies', () {
      final result = TripHistoryView.completeMonthName(
        dates: ['2026-05-16'],
        legsByDate: {
          '2026-05-16': [leg(date: '2026-05-16', synced: false)],
        },
        draftCount: 0,
      );
      expect(result, isNull);
    });
  });
}
