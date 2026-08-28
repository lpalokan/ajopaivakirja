import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The pre-v8 shape: päiväraha existed only as a number on a leg.
const _createLegacyLegs = '''
  CREATE TABLE trip_legs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    leg_order INTEGER NOT NULL,
    start_time TEXT NOT NULL,
    end_time TEXT,
    start_odometer INTEGER NOT NULL,
    end_odometer INTEGER,
    start_location TEXT NOT NULL,
    end_location TEXT,
    daily_allowance REAL NOT NULL DEFAULT 0,
    daily_allowance_type INTEGER
  )
''';

const _createSettings = '''
  CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)
''';

Future<Database> _legacyDb({
  double halfDay = 25.0,
  double fullDay = 54.0,
}) async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute(_createLegacyLegs);
  await db.execute(_createSettings);
  await db.insert('settings', {'key': 'allowance_6h', 'value': '$halfDay'});
  await db.insert('settings', {'key': 'allowance_10h', 'value': '$fullDay'});
  return db;
}

Future<void> _insertLeg(
  Database db, {
  required String date,
  required int legOrder,
  required String startTime,
  double dailyAllowance = 0,
  int? dailyAllowanceType,
}) async {
  await db.insert('trip_legs', {
    'date': date,
    'leg_order': legOrder,
    'start_time': startTime,
    'start_odometer': 1000,
    'start_location': 'Koti',
    'end_location': 'Työ',
    'daily_allowance': dailyAllowance,
    'daily_allowance_type': dailyAllowanceType,
  });
}

Future<List<Map<String, Object?>>> _allowances(Database db) =>
    db.query('daily_allowances', orderBy: 'date ASC');

void main() {
  setUpAll(sqfliteFfiInit);

  group('backfillDailyAllowancesFromLegs', () {
    test('gives a legacy päiväraha its own row', () async {
      final db = await _legacyDb();
      addTearDown(db.close);
      await _insertLeg(
        db,
        date: '2026-03-02',
        legOrder: 1,
        startTime: '2026-03-02T07:30:00.000',
      );
      await _insertLeg(
        db,
        date: '2026-03-02',
        legOrder: 2,
        startTime: '2026-03-02T16:00:00.000',
        dailyAllowance: 54.0,
      );

      expect(await DatabaseService.backfillDailyAllowancesFromLegs(db), 1);

      final rows = await _allowances(db);
      expect(rows, hasLength(1));
      expect(rows.single['date'], '2026-03-02');
      expect(rows.single['amount'], 54.0);
      // The travel day starts when the driver left, not when the leg that
      // happens to carry the figure did.
      expect(rows.single['period_start'], '2026-03-02T07:30:00.000');
    });

    test('preserves the day total exactly', () async {
      // Whatever the legs say the day paid is what the day paid. The
      // migration is not allowed to recompute it — a tax figure the user has
      // already filed must not move.
      final db = await _legacyDb();
      addTearDown(db.close);
      await _insertLeg(
        db,
        date: '2026-03-03',
        legOrder: 1,
        startTime: '2026-03-03T06:00:00.000',
        dailyAllowance: 17.5,
      );

      await DatabaseService.backfillDailyAllowancesFromLegs(db);

      expect((await _allowances(db)).single['amount'], 17.5);
    });

    test('keeps a manual type over anything it could infer', () async {
      final db = await _legacyDb();
      addTearDown(db.close);
      await _insertLeg(
        db,
        date: '2026-03-04',
        legOrder: 1,
        startTime: '2026-03-04T06:00:00.000',
        dailyAllowance: 54.0,
        dailyAllowanceType: 1,
      );

      await DatabaseService.backfillDailyAllowancesFromLegs(db);

      expect((await _allowances(db)).single['type'], 1);
    });

    test('reads an automatic allowance back as full or half', () async {
      final db = await _legacyDb();
      addTearDown(db.close);
      await _insertLeg(
        db,
        date: '2026-03-05',
        legOrder: 1,
        startTime: '2026-03-05T06:00:00.000',
        dailyAllowance: 54.0,
      );
      await _insertLeg(
        db,
        date: '2026-03-06',
        legOrder: 1,
        startTime: '2026-03-06T06:00:00.000',
        dailyAllowance: 25.0,
      );

      await DatabaseService.backfillDailyAllowancesFromLegs(db);

      final rows = await _allowances(db);
      expect(rows.map((r) => r['type']), [2, 1]);
    });

    test('honours the user\'s own allowance amounts', () async {
      final db = await _legacyDb(halfDay: 20.0, fullDay: 48.0);
      addTearDown(db.close);
      await _insertLeg(
        db,
        date: '2026-03-07',
        legOrder: 1,
        startTime: '2026-03-07T06:00:00.000',
        dailyAllowance: 48.0,
      );

      await DatabaseService.backfillDailyAllowancesFromLegs(db);

      expect((await _allowances(db)).single['type'], 2);
    });

    test('skips a date the allowance table already covers', () async {
      // A trip finalized since v8 owns its rows, and they know about travel
      // days the legs never did. Backfilling over them would double-pay.
      final db = await _legacyDb();
      addTearDown(db.close);
      await _insertLeg(
        db,
        date: '2026-03-08',
        legOrder: 1,
        startTime: '2026-03-08T06:00:00.000',
        dailyAllowance: 54.0,
      );
      await DatabaseService.backfillDailyAllowancesFromLegs(db);

      expect(await DatabaseService.backfillDailyAllowancesFromLegs(db), 0);
      expect(await _allowances(db), hasLength(1));
    });

    test('leaves days that earned nothing alone', () async {
      final db = await _legacyDb();
      addTearDown(db.close);
      await _insertLeg(
        db,
        date: '2026-03-09',
        legOrder: 1,
        startTime: '2026-03-09T06:00:00.000',
      );

      expect(await DatabaseService.backfillDailyAllowancesFromLegs(db), 0);
      expect(await _allowances(db), isEmpty);
    });

    test('runs on a database that has never had a trip', () async {
      final db = await _legacyDb();
      addTearDown(db.close);

      expect(await DatabaseService.backfillDailyAllowancesFromLegs(db), 0);
      expect(await _allowances(db), isEmpty);
    });
  });
}
