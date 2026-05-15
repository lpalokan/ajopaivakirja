import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/route.dart';
import '../models/trip_leg.dart';
import '../models/app_settings.dart';
import '../models/km_rate.dart';
import '../models/expense.dart';
import '../models/location_zone.dart';
import 'log_service.dart';

class DatabaseService {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  static Future<Database> _init() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'kilometrikorvaus.db');

    return openDatabase(
      path,
      version: 6,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE routes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        start_location TEXT NOT NULL,
        end_location TEXT NOT NULL,
        distance_km REAL NOT NULL,
        last_purpose TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE trip_legs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        leg_order INTEGER NOT NULL,
        route_id INTEGER,
        start_time TEXT NOT NULL,
        end_time TEXT,
        start_odometer INTEGER NOT NULL,
        end_odometer INTEGER,
        start_location TEXT NOT NULL,
        end_location TEXT,
        route_description TEXT,
        km_driven REAL NOT NULL DEFAULT 0,
        working_time_hours REAL NOT NULL DEFAULT 0,
        leg_duration_hours REAL NOT NULL DEFAULT 0,
        purpose TEXT,
        driver TEXT NOT NULL,
        km_allowance REAL NOT NULL DEFAULT 0,
        daily_allowance REAL NOT NULL DEFAULT 0,
        daily_allowance_type INTEGER,
        is_return_home INTEGER NOT NULL DEFAULT 0,
        synced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (route_id) REFERENCES routes(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE deleted_leg_ids (
        id INTEGER PRIMARY KEY,
        deleted_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE km_rates (
        year INTEGER PRIMARY KEY,
        rate REAL NOT NULL
      )
    ''');

    await _seedKmRates(db);

    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_leg_id INTEGER,
        type INTEGER NOT NULL,
        amount REAL NOT NULL,
        description TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (trip_leg_id) REFERENCES trip_legs(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE location_zones (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        radius_meters REAL NOT NULL DEFAULT 200,
        created_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        ALTER TABLE trip_legs ADD COLUMN daily_allowance_type INTEGER
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE deleted_leg_ids (
          id INTEGER PRIMARY KEY,
          deleted_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE location_zones (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          radius_meters REAL NOT NULL DEFAULT 200,
          created_at TEXT NOT NULL
        )
      ''');
    }
  }

  static Future<void> _seedKmRates(Database db) async {
    final batch = db.batch();
    for (final entry in KmRate.finnishDefaults.entries) {
      batch.insert(
        'km_rates',
        {'year': entry.key, 'rate': entry.value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // ── Routes ──

  static Future<Route> insertRoute(Route route) async {
    final db = await database;
    final id = await db.insert('routes', route.toMap());
    return route.copyWith(id: id);
  }

  static Future<Route> updateRoute(Route route) async {
    final db = await database;
    await db.update(
      'routes',
      route.toMap(),
      where: 'id = ?',
      whereArgs: [route.id],
    );
    return route;
  }

  static Future<void> deleteRoute(int id) async {
    final db = await database;
    await db.delete('routes', where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<Route>> getAllRoutes() async {
    final db = await database;
    final maps = await db.query('routes', orderBy: 'updated_at DESC');
    return maps.map((m) => Route.fromMap(m)).toList();
  }

  static Future<Route?> getRoute(int id) async {
    final db = await database;
    final maps = await db.query('routes', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Route.fromMap(maps.first);
  }

  static Future<List<Route>> getRecentRoutes({int limit = 2}) async {
    final db = await database;
    final maps = await db.query(
      'routes',
      orderBy: 'updated_at DESC',
      limit: limit,
    );
    return maps.map((m) => Route.fromMap(m)).toList();
  }

  static Future<List<String>> getUniqueLocations() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT DISTINCT start_location as loc FROM routes '
      'UNION SELECT DISTINCT end_location as loc FROM routes ORDER BY loc',
    );
    return result.map((r) => r['loc'] as String).toList();
  }

  static Future<void> updateRouteLastPurpose(int routeId, String purpose) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'routes',
      {'last_purpose': purpose, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [routeId],
    );
  }

  static Future<void> updateRouteTimestamp(int routeId) async {
    final db = await database;
    await db.update(
      'routes',
      {'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [routeId],
    );
  }

  // ── Trip Legs ──

  static Future<TripLeg> insertTripLeg(TripLeg leg) async {
    final db = await database;
    final id = await db.insert('trip_legs', leg.toMap());
    LogService().info('DB: inserted leg $id (${leg.startLocation} -> ${leg.endLocation})');
    return leg.copyWith(id: id);
  }

  static Future<TripLeg> updateTripLeg(TripLeg leg) async {
    final db = await database;
    await db.update(
      'trip_legs',
      leg.toMap(),
      where: 'id = ?',
      whereArgs: [leg.id],
    );
    LogService().info('DB: updated leg ${leg.id}');
    return leg;
  }

  static Future<void> deleteTripLeg(int id) async {
    final db = await database;
    await db.delete('trip_legs', where: 'id = ?', whereArgs: [id]);
    await db.insert('deleted_leg_ids', {
      'id': id,
      'deleted_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    LogService().info('DB: deleted leg $id');
  }

  static Future<List<int>> getDeletedLegIds() async {
    final db = await database;
    final result = await db.query('deleted_leg_ids');
    return result.map((r) => r['id'] as int).toList();
  }

  static Future<void> clearDeletedLegIds(List<int> ids) async {
    final db = await database;
    for (final id in ids) {
      await db.delete('deleted_leg_ids', where: 'id = ?', whereArgs: [id]);
    }
  }

  static Future<List<TripLeg>> getLegsForDate(String date) async {
    final db = await database;
    final maps = await db.query(
      'trip_legs',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'leg_order ASC',
    );
    return maps.map((m) => TripLeg.fromMap(m)).toList();
  }

  static Future<List<TripLeg>> getAllLegs() async {
    final db = await database;
    final maps = await db.query(
      'trip_legs',
      orderBy: 'date DESC, leg_order ASC',
    );
    return maps.map((m) => TripLeg.fromMap(m)).toList();
  }

  static Future<List<String>> getDistinctDates() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT DISTINCT date FROM trip_legs ORDER BY date DESC',
    );
    return result.map((r) => r['date'] as String).toList();
  }

  static Future<List<TripLeg>> getUnsyncedLegs() async {
    final db = await database;
    final maps = await db.query(
      'trip_legs',
      where: 'synced = 0',
      orderBy: 'date ASC, leg_order ASC',
    );
    return maps.map((m) => TripLeg.fromMap(m)).toList();
  }

  static Future<void> markLegSynced(int id) async {
    final db = await database;
    await db.update(
      'trip_legs',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> markLegUnsynced(int id) async {
    final db = await database;
    await db.update(
      'trip_legs',
      {'synced': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    LogService().info('DB: leg $id marked unsynced');
  }

  static Future<int> getNextLegOrder(String date) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT MAX(leg_order) as max_order FROM trip_legs WHERE date = ?',
      [date],
    );
    final maxOrder = (result.first['max_order'] as int?) ?? 0;
    return maxOrder + 1;
  }

  static Future<TripLeg?> getLastLeg() async {
    final db = await database;
    final maps = await db.query(
      'trip_legs',
      orderBy: 'date DESC, leg_order DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return TripLeg.fromMap(maps.first);
  }

  static Future<TripLeg?> getActiveLeg() async {
    final db = await database;
    final maps = await db.query(
      'trip_legs',
      where: 'end_time IS NULL',
      orderBy: 'date DESC, leg_order DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return TripLeg.fromMap(maps.first);
  }

  // ── Km Rates ──

  static Future<Map<int, double>> getAllKmRates() async {
    final db = await database;
    final maps = await db.query('km_rates', orderBy: 'year DESC');
    final result = <int, double>{};
    for (final m in maps) {
      result[m['year'] as int] = (m['rate'] as num).toDouble();
    }
    return result;
  }

  static Future<double?> getKmRateForYear(int year) async {
    final db = await database;
    final maps = await db.query(
      'km_rates',
      where: 'year = ?',
      whereArgs: [year],
    );
    if (maps.isEmpty) return null;
    return (maps.first['rate'] as num).toDouble();
  }

  static Future<void> upsertKmRate(int year, double rate) async {
    final db = await database;
    await db.insert(
      'km_rates',
      {'year': year, 'rate': rate},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> deleteKmRate(int year) async {
    final db = await database;
    await db.delete('km_rates', where: 'year = ?', whereArgs: [year]);
  }

  // ── Settings ──

  static Future<void> saveSettings(AppSettings settings) async {
    final db = await database;
    final batch = db.batch();
    for (final entry in settings.toMap().entries) {
      batch.insert(
        'settings',
        {'key': entry.key, 'value': entry.value},
        conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
    await batch.commit(noResult: true);
  }

  static Future<AppSettings> loadSettings() async {
    final db = await database;
    final maps = await db.query('settings');
    final map = <String, String>{};
    for (final row in maps) {
      map[row['key'] as String] = row['value'] as String;
    }
    return AppSettings.fromMap(map);
  }

  static Future<String?> getSetting(String key) async {
    final db = await database;
    final maps = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (maps.isEmpty) return null;
    return maps.first['value'] as String;
  }

  // ── Expenses ──

  static Future<Expense> insertExpense(Expense expense) async {
    final db = await database;
    final id = await db.insert('expenses', expense.toMap());
    LogService().info('DB: inserted expense $id (${expense.type.displayName}, ${expense.amount}€)');
    return expense.copyWith(id: id);
  }

  static Future<void> deleteExpense(int id) async {
    final db = await database;
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
    LogService().info('DB: deleted expense $id');
  }

  static Future<List<Expense>> getExpensesForLeg(int legId) async {
    final db = await database;
    final maps = await db.query(
      'expenses',
      where: 'trip_leg_id = ?',
      whereArgs: [legId],
      orderBy: 'created_at ASC',
    );
    return maps.map((m) => Expense.fromMap(m)).toList();
  }

  static Future<Map<int, List<Expense>>> getExpensesForLegs(List<int> legIds) async {
    if (legIds.isEmpty) return {};
    final db = await database;
    final placeholders = legIds.map((_) => '?').join(',');
    final maps = await db.query(
      'expenses',
      where: 'trip_leg_id IN ($placeholders)',
      whereArgs: legIds,
      orderBy: 'created_at ASC',
    );
    final result = <int, List<Expense>>{};
    for (final legId in legIds) {
      result[legId] = [];
    }
    for (final map in maps) {
      final expense = Expense.fromMap(map);
      final legId = expense.tripLegId;
      if (legId != null) {
        result[legId]?.add(expense);
      }
    }
    return result;
  }

  static Future<List<Expense>> getExpensesForDate(String date) async {
    final db = await database;
    final maps = await db.rawQuery(
      '''SELECT e.* FROM expenses e
         INNER JOIN trip_legs tl ON e.trip_leg_id = tl.id
         WHERE tl.date = ?
         ORDER BY e.created_at ASC''',
      [date],
    );
    return maps.map((m) => Expense.fromMap(m)).toList();
  }

  // ── Location Zones ──

  static Future<LocationZone> insertLocationZone(LocationZone zone) async {
    final db = await database;
    final id = await db.insert('location_zones', zone.toMap());
    LogService().info('DB: inserted location zone $id (${zone.name})');
    return zone.copyWith(id: id);
  }

  static Future<void> updateLocationZone(LocationZone zone) async {
    final db = await database;
    await db.update(
      'location_zones',
      zone.toMap(),
      where: 'id = ?',
      whereArgs: [zone.id],
    );
  }

  static Future<void> deleteLocationZone(int id) async {
    final db = await database;
    await db.delete('location_zones', where: 'id = ?', whereArgs: [id]);
    LogService().info('DB: deleted location zone $id');
  }

  static Future<List<LocationZone>> getAllLocationZones() async {
    final db = await database;
    final maps = await db.query('location_zones', orderBy: 'name ASC');
    return maps.map((m) => LocationZone.fromMap(m)).toList();
  }
}
