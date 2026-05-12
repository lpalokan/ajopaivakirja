import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/route.dart' as model;
import '../models/trip_leg.dart';
import '../models/app_settings.dart';
import '../services/database_service.dart';
import '../services/trip_calculator.dart';
import '../main.dart';
import 'settings_provider.dart';

class TripState {
  final TripLeg? activeLeg;
  final List<TripLeg> todayLegs;
  final String? lastArrivalLocation;

  const TripState({
    this.activeLeg,
    this.todayLegs = const [],
    this.lastArrivalLocation,
  });

  TripState copyWith({
    TripLeg? activeLeg,
    List<TripLeg>? todayLegs,
    String? lastArrivalLocation,
  }) {
    return TripState(
      activeLeg: activeLeg ?? this.activeLeg,
      todayLegs: todayLegs ?? this.todayLegs,
      lastArrivalLocation: lastArrivalLocation ?? this.lastArrivalLocation,
    );
  }
}

class TripNotifier extends StateNotifier<TripState> {
  final Ref _ref;

  TripNotifier(this._ref) : super(const TripState());

  AppSettings get _settings => _ref.read(settingsProvider);

  TripCalculator get _calculator => TripCalculator(_settings);

  String get _today => DateFormat('yyyy-MM-dd').format(DateTime.now());

  bool get isDriving => state.activeLeg != null;

  Future<void> load() async {
    final legs = await DatabaseService.getLegsForDate(_today);
    final activeLeg = await DatabaseService.getActiveLeg();
    final lastLeg = await DatabaseService.getLastLeg();

    state = TripState(
      activeLeg: activeLeg,
      todayLegs: legs,
      lastArrivalLocation: lastLeg?.endLocation,
    );
  }

  /// Determine direction (start → end or end → start) based on last arrival.
  ({String start, String end}) _determineDirection(model.Route route) {
    final lastArrival = state.lastArrivalLocation;

    if (lastArrival != null) {
      final last = lastArrival.trim().toLowerCase();
      final routeStart = route.startLocation.trim().toLowerCase();
      final routeEnd = route.endLocation.trim().toLowerCase();

      if (last == routeEnd) {
        return (start: route.endLocation, end: route.startLocation);
      }
      if (last == routeStart) {
        return (start: route.startLocation, end: route.endLocation);
      }
    }

    return (start: route.startLocation, end: route.endLocation);
  }

  Future<TripLeg> startDriving({
    required model.Route route,
    required int startOdometer,
    required String purpose,
    String? driver,
  }) async {
    final dir = _determineDirection(route);
    final driverName = driver ?? _settings.driverName;
    final now = DateTime.now();
    final legOrder = await DatabaseService.getNextLegOrder(_today);

    final leg = TripLeg(
      date: _today,
      legOrder: legOrder,
      routeId: route.id,
      startTime: now,
      startOdometer: startOdometer,
      startLocation: dir.start,
      endLocation: dir.end,
      kmDriven: route.distanceKm,
      routeDescription: route.name,
      purpose: purpose,
      driver: driverName,
    );

    final saved = await DatabaseService.insertTripLeg(leg);
    await DatabaseService.updateRouteTimestamp(route.id!);

    final todayLegs = await DatabaseService.getLegsForDate(_today);

    state = state.copyWith(
      activeLeg: saved,
      todayLegs: todayLegs,
    );

    return saved;
  }

  Future<TripLeg> stopDriving(int endOdometer) async {
    final active = state.activeLeg;
    if (active == null) throw Exception('Ei aktiivista ajoa');

    final now = DateTime.now();
    var leg = active.copyWith(
      endTime: now,
      endOdometer: endOdometer,
    );

    leg = _calculator.calculateLeg(leg);
    await DatabaseService.updateTripLeg(leg);

    final isReturnHome = leg.isReturnHome;

    String? lastArrival = leg.endLocation;

    if (isReturnHome) {
      final dayLegs = await DatabaseService.getLegsForDate(_today);
      await _calculator.finalizeDay(dayLegs);
      _syncToSheets(dayLegs);
    }

    final todayLegs = await DatabaseService.getLegsForDate(_today);

    state = state.copyWith(
      activeLeg: null,
      todayLegs: todayLegs,
      lastArrivalLocation: lastArrival,
    );

    return leg;
  }

  Future<void> extendReminder() async {
    await load();
  }

  Future<void> _syncToSheets(List<TripLeg> legs) async {
    final settings = _ref.read(settingsProvider);
    if (settings.sheetId.isEmpty) return;

    try {
      final sheets = _ref.read(sheetsServiceProvider);
      await sheets.appendLegs(
        legs,
        sheetId: settings.sheetId,
        sheetTab: settings.sheetTab,
        onSynced: (legId) => DatabaseService.markLegSynced(legId),
      );
    } catch (_) {
      // Sheets sync failed silently — app continues working locally.
      // User can retry later via manual sync.
    }
  }

  Future<void> finalizeDay() async {
    final legs = await DatabaseService.getLegsForDate(_today);
    if (legs.isNotEmpty) {
      await _calculator.finalizeDay(legs);
    }
    await load();
  }

  /// Get today's day summary for display.
  ({double totalKm, double totalKmAllowance, double totalDailyAllowance,
      double grandTotal, double totalHours}) get daySummary {
    final legs = state.todayLegs;
    final summary = _calculator.summarizeDay(legs);
    final totalHours = legs.isNotEmpty
        ? legs.last.endTime
                ?.difference(legs.first.startTime)
                .inMinutes
                .toDouble() ??
            0 / 60.0
        : 0.0;

    return (
      totalKm: summary.totalKm,
      totalKmAllowance: summary.totalKmAllowance,
      totalDailyAllowance: summary.totalDailyAllowance,
      grandTotal: summary.grandTotal,
      totalHours: totalHours,
    );
  }
}

final tripProvider = StateNotifierProvider<TripNotifier, TripState>((ref) {
  return TripNotifier(ref);
});
