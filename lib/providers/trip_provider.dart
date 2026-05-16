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

    state = state.copyWith(
      activeLeg: saved,
      todayLegs: todayLegs,
    );

    return saved;
  }

  Future<TripLeg> stopDriving(int endOdometer, {DateTime? endTime}) async {
    final active = state.activeLeg;
    if (active == null) throw Exception('Ei aktiivista ajoa');

    final time = endTime ?? DateTime.now();
    var leg = active.copyWith(
      endTime: time,
      endOdometer: endOdometer,
    );

    leg = _calculator.calculateLeg(leg);
    LogService().info('Trip: stopped (odo: $endOdometer, km: ${leg.kmDriven}, returnHome: ${leg.isReturnHome})');
    await DatabaseService.updateTripLeg(leg);

    if (leg.isReturnHome) {
      final dayLegs = await DatabaseService.getLegsForDate(_today);
      LogService().info('Trip: finalizing day with ${dayLegs.length} legs');
      final updatedDayLegs = await _calculator.finalizeDay(dayLegs);
      _syncToSheets(updatedDayLegs);
    }

    final todayLegs = await DatabaseService.getLegsForDate(_today);

    state = state.copyWith(
      activeLeg: null,
      todayLegs: todayLegs,
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
