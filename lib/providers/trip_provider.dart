import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/route.dart' as model;
import '../models/trip_leg.dart';
import '../models/app_settings.dart';
import '../services/database_service.dart';
import '../services/trip_calculator.dart';
import '../services/log_service.dart';
import '../main.dart';
import 'settings_provider.dart';
import 'route_provider.dart';

class _Sentinel {
  const _Sentinel();
}

class TripState {
  final TripLeg? activeLeg;
  final List<TripLeg> todayLegs;

  const TripState({
    this.activeLeg,
    this.todayLegs = const [],
  });

  static const _unset = _Sentinel();

  TripState copyWith({
    Object? activeLeg = _unset,
    List<TripLeg>? todayLegs,
  }) {
    return TripState(
      activeLeg: identical(activeLeg, _unset)
          ? this.activeLeg
          : activeLeg as TripLeg?,
      todayLegs: todayLegs ?? this.todayLegs,
    );
  }
}

class TripNotifier extends StateNotifier<TripState> {
  final Ref _ref;
  Map<int, double>? _kmRates;

  TripNotifier(this._ref) : super(const TripState());

  AppSettings get _settings => _ref.read(settingsProvider);

  TripCalculator get _calculator =>
      TripCalculator(_settings, kmRates: _kmRates);

  Future<void> loadKmRates() async {
    _kmRates = await DatabaseService.getAllKmRates();
  }

  String get _today => DateFormat('yyyy-MM-dd').format(DateTime.now());

  bool get isDriving => state.activeLeg != null;

  Future<void> load() async {
    final legs = await DatabaseService.getLegsForDate(_today);
    final activeLeg = await DatabaseService.getActiveLeg();
    if (!mounted) return;

    state = TripState(
      activeLeg: activeLeg,
      todayLegs: legs,
    );
  }

  Future<TripLeg> startDriving({
    required model.Route route,
    required int startOdometer,
    required String purpose,
    String? driver,
    DateTime? startTime,
  }) async {
    final driverName = driver ?? _settings.driverName;
    final time = startTime ?? DateTime.now();
    final legOrder = await DatabaseService.getNextLegOrder(_today);

    final leg = TripLeg(
      date: _today,
      legOrder: legOrder,
      routeId: route.id,
      startTime: time,
      startOdometer: startOdometer,
      startLocation: route.startLocation,
      endLocation: route.endLocation,
      kmDriven: route.distanceKm,
      routeDescription: route.name,
      purpose: purpose,
      driver: driverName,
    );

    final saved = await DatabaseService.insertTripLeg(leg);
    LogService().info('Trip: started ${route.name} (odo: $startOdometer, leg #$legOrder)');
    await DatabaseService.updateRouteTimestamp(route.id!);

    final todayLegs = await DatabaseService.getLegsForDate(_today);
    if (!mounted) return saved;

    state = state.copyWith(
      activeLeg: saved,
      todayLegs: todayLegs,
    );

    return saved;
  }

  /// Start an ad-hoc trip that is not based on a predefined route.
  Future<TripLeg> startAdHocDriving({
    required int startOdometer,
    required String startLocation,
    String purpose = '',
    String? driver,
    DateTime? startTime,
  }) async {
    final driverName = driver ?? _settings.driverName;
    final time = startTime ?? DateTime.now();
    final legOrder = await DatabaseService.getNextLegOrder(_today);

    final leg = TripLeg(
      date: _today,
      legOrder: legOrder,
      routeId: null,
      startTime: time,
      startOdometer: startOdometer,
      startLocation: startLocation,
      endLocation: null,
      kmDriven: 0,
      routeDescription: null,
      purpose: purpose,
      driver: driverName,
    );

    final saved = await DatabaseService.insertTripLeg(leg);
    LogService().info(
        'Trip: started ad-hoc from $startLocation (odo: $startOdometer, leg #$legOrder)');

    final todayLegs = await DatabaseService.getLegsForDate(_today);
    if (!mounted) return saved;
    state = state.copyWith(activeLeg: saved, todayLegs: todayLegs);
    return saved;
  }

  Future<TripLeg> stopDriving(
    int endOdometer, {
    DateTime? endTime,
    String? endLocation,
    String? purpose,
  }) async {
    final active = state.activeLeg;
    if (active == null) throw Exception('Ei aktiivista ajoa');

    final time = endTime ?? DateTime.now();
    var leg = active.copyWith(
      endTime: time,
      endOdometer: endOdometer,
      endLocation: (endLocation != null && endLocation.isNotEmpty)
          ? endLocation
          : active.endLocation,
      purpose: (purpose != null && purpose.isNotEmpty)
          ? purpose
          : active.purpose,
    );

    final wasAdHoc = active.routeId == null && active.routeDescription == null;

    leg = _calculator.calculateLeg(leg);
    LogService().info('Trip: stopped (odo: $endOdometer, km: ${leg.kmDriven}, returnHome: ${leg.isReturnHome})');
    await DatabaseService.updateTripLeg(leg);

    // The trip may have stopped while the screen/provider was being torn
    // down (e.g. test teardown); don't touch providers/state after dispose.
    if (!mounted) return leg;

    // Persist an ad-hoc journey as a reusable route (also makes its start
    // and end locations available as suggestions next time).
    if (wasAdHoc &&
        leg.endLocation != null &&
        leg.endLocation!.isNotEmpty &&
        leg.startLocation.isNotEmpty) {
      await _saveAdHocRoute(leg);
    }

    if (leg.isReturnHome) {
      final dayLegs = await DatabaseService.getLegsForDate(_today);
      LogService().info('Trip: finalizing day with ${dayLegs.length} legs');
      final updatedDayLegs = await _calculator.finalizeDay(dayLegs);
      _syncToSheets(updatedDayLegs);
    }

    final todayLegs = await DatabaseService.getLegsForDate(_today);
    if (!mounted) return leg;

    state = state.copyWith(
      activeLeg: null,
      todayLegs: todayLegs,
    );

    return leg;
  }

  Future<void> extendReminder() async {
    await load();
  }

  /// Cancel the active trip without recording it.
  Future<void> cancelDriving() async {
    final active = state.activeLeg;
    if (active == null || active.id == null) return;

    await DatabaseService.deleteTripLeg(active.id!);
    LogService().info('Trip: cancelled leg ${active.id}');

    final todayLegs = await DatabaseService.getLegsForDate(_today);
    if (!mounted) return;
    state = state.copyWith(activeLeg: null, todayLegs: todayLegs);
  }

  Future<void> _saveAdHocRoute(TripLeg leg) async {
    final start = leg.startLocation.trim();
    final end = leg.endLocation!.trim();
    final routeNotifier = _ref.read(routeProvider.notifier);

    final exists = _ref.read(routeProvider).any((r) =>
        r.startLocation.trim().toLowerCase() == start.toLowerCase() &&
        r.endLocation.trim().toLowerCase() == end.toLowerCase());
    if (exists) return;

    final now = DateTime.now();
    await routeNotifier.add(model.Route(
      name: '$start → $end',
      startLocation: start,
      endLocation: end,
      distanceKm: leg.kmDriven,
      lastPurpose:
          (leg.purpose != null && leg.purpose!.isNotEmpty) ? leg.purpose : null,
      createdAt: now,
      updatedAt: now,
    ));
    LogService().info('Trip: saved ad-hoc route $start -> $end (${leg.kmDriven} km)');
  }

  Future<void> _syncToSheets(List<TripLeg> legs) async {
    final settings = _ref.read(settingsProvider);
    if (settings.sheetId.isEmpty) return;

    try {
      final sheets = _ref.read(sheetsServiceProvider);
      final deletedIds = await DatabaseService.getDeletedLegIds();
      LogService().info('Sheets: syncing ${legs.length} legs to ${settings.sheetTab} (+ ${deletedIds.length} deletes)');
      await sheets.appendLegs(
        legs,
        sheetId: settings.sheetId,
        sheetTab: settings.sheetTab,
        deletedLegIds: deletedIds,
        onSynced: (legId) => DatabaseService.markLegSynced(legId),
      );
      if (deletedIds.isNotEmpty) {
        await DatabaseService.clearDeletedLegIds(deletedIds);
      }
      LogService().info('Sheets: sync complete (${legs.length} legs)');
    } catch (e, st) {
      LogService().error('Sheets: sync failed', e, st);
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
    final totalHours = legs.isNotEmpty ? legs.last.legDurationHours : 0.0;

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
