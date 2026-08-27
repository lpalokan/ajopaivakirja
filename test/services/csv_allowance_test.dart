import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/models/daily_allowance.dart';
import 'package:kilometrikorvaus/models/trip_leg.dart';
import 'package:kilometrikorvaus/services/allowance_ledger.dart';
import 'package:kilometrikorvaus/services/csv_export_service.dart';

/// A three-day työmatka: drive out on the 15th, stay put on the 16th, drive
/// home on the 17th. The 16th is a travel day with no leg — the day every
/// export used to lose.
final _outbound = TripLeg(
  id: 1,
  date: '2026-05-15',
  legOrder: 1,
  startTime: DateTime(2026, 5, 15, 8),
  endTime: DateTime(2026, 5, 15, 11),
  startOdometer: 1000,
  endOdometer: 1300,
  startLocation: 'Koti',
  endLocation: 'Asiakas',
  kmDriven: 300,
  kmAllowance: 165.0,
  driver: 'Lapa',
);

final _return = TripLeg(
  id: 2,
  date: '2026-05-17',
  legOrder: 1,
  startTime: DateTime(2026, 5, 17, 9),
  endTime: DateTime(2026, 5, 17, 12),
  startOdometer: 1300,
  endOdometer: 1600,
  startLocation: 'Asiakas',
  endLocation: 'Koti',
  kmDriven: 300,
  kmAllowance: 165.0,
  isReturnHome: true,
  driver: 'Lapa',
);

DailyAllowance _day(String date, {int type = 2, double amount = 54.0}) =>
    DailyAllowance(
      date: date,
      periodStart: '${date}T08:00:00.000',
      type: type,
      amount: amount,
      createdAt: '2026-05-17T12:00:00.000',
    );

final _ledger = AllowanceLedger([
  _day('2026-05-15'),
  _day('2026-05-16'),
  _day('2026-05-17', type: 1, amount: 25.0),
]);

/// The columns of one CSV record, header included.
List<String> _cells(String line) => line.split(',');

const _dateColumn = 0;
const _allowanceColumn = 13;
const _typeColumn = 14;
const _rowKindColumn = 18;

List<List<String>> _dataRows(String content) => content
    .split('\r\n')
    .where((l) => l.trim().isNotEmpty)
    .skip(1) // header
    .map(_cells)
    .toList();

void main() {
  group('a travel day with no driving', () {
    test('gets a row of its own', () {
      final rows = _dataRows(
        CsvExportService.generateContent([_outbound, _return], ledger: _ledger),
      );

      final missingDay = rows.where((r) => r[_dateColumn] == '2026-05-16');
      expect(
        missingDay,
        hasLength(1),
        reason: 'the middle day of the trip is missing from the export',
      );
      expect(missingDay.single[_allowanceColumn], '54.00');
      expect(missingDay.single[_rowKindColumn], 'Päiväraha');
    });

    test('lands in date order, between the days it separates', () {
      final rows = _dataRows(
        CsvExportService.generateContent([_outbound, _return], ledger: _ledger),
      );

      expect(rows.map((r) => r[_dateColumn]), [
        '2026-05-15',
        '2026-05-16',
        '2026-05-17',
      ]);
    });

    test('makes the exported total match what the trip actually paid', () {
      // The whole point. Before the ledger the file added up to 79 € of
      // päivärahaa for a trip that earned 133 €.
      final rows = _dataRows(
        CsvExportService.generateContent([_outbound, _return], ledger: _ledger),
      );

      final exported = rows.fold<double>(
        0,
        (sum, r) => sum + (double.tryParse(r[_allowanceColumn]) ?? 0),
      );
      expect(exported, _ledger.total);
      expect(exported, 133.0);
    });
  });

  group('a day that was driven', () {
    test('carries its päiväraha and names its type', () {
      final rows = _dataRows(
        CsvExportService.generateContent([_outbound, _return], ledger: _ledger),
      );

      final lastDay = rows.firstWhere((r) => r[_dateColumn] == '2026-05-17');
      expect(lastDay[_allowanceColumn], '25.00');
      expect(lastDay[_typeColumn], 'Puolipäivä (>6h)');
      expect(lastDay[_rowKindColumn], 'Matka');
    });

    test('puts the day on its last leg only', () {
      final second = TripLeg(
        id: 3,
        date: '2026-05-15',
        legOrder: 2,
        startTime: DateTime(2026, 5, 15, 14),
        endTime: DateTime(2026, 5, 15, 15),
        startOdometer: 1300,
        endOdometer: 1310,
        startLocation: 'Asiakas',
        endLocation: 'Asiakas 2',
        kmDriven: 10,
        driver: 'Lapa',
      );

      final rows = _dataRows(
        CsvExportService.generateContent([
          _outbound,
          second,
        ], ledger: AllowanceLedger([_day('2026-05-15')])),
      );

      expect(rows.map((r) => r[_allowanceColumn]), ['0.00', '54.00']);
      // A type printed against a 0,00 row reads like a second payment.
      expect(rows.first[_typeColumn], '');
    });

    test('a draft never carries the day', () {
      // Drafts are filtered from the file, so the day's figure has to move to
      // the last leg that is actually exported.
      final draft = TripLeg(
        id: 4,
        date: '2026-05-15',
        legOrder: 2,
        startTime: DateTime(2026, 5, 15, 14),
        startOdometer: 1300,
        startLocation: 'Asiakas',
        driver: 'Lapa',
      );

      final rows = _dataRows(
        CsvExportService.generateContent([
          _outbound,
          draft,
        ], ledger: AllowanceLedger([_day('2026-05-15')])),
      );

      expect(rows, hasLength(1));
      expect(rows.single[_allowanceColumn], '54.00');
    });
  });

  test('every row has the same number of columns as the header', () {
    final content = CsvExportService.generateContent([
      _outbound,
      _return,
    ], ledger: _ledger);
    final lines = content.split('\r\n').where((l) => l.trim().isNotEmpty);
    final width = _cells(lines.first).length;

    for (final line in lines) {
      expect(_cells(line), hasLength(width), reason: 'ragged row: $line');
    }
  });
}
