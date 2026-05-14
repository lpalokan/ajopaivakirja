import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/route.dart';
import '../models/trip_leg.dart';
import '../models/app_settings.dart';
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
      version: 2,
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
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        ALTER TABLE trip_legs ADD COLUMN daily_allowance_type INTEGER
      ''');
    }
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
    LogService().info('DB: deleted leg $id');
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
}
