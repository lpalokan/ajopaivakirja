// TripNotifier receives a BuildContext as a method parameter from widget
// callers; the lint doesn't account for StateNotifier-as-orchestrator usage.
// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/route.dart' as model;
import '../models/trip_leg.dart';
import '../models/app_settings.dart';
import '../services/database_service.dart';
import '../services/trip_calculator.dart';
import '../services/log_service.dart';
import '../widgets/odometer_dialog.dart';
import '../main.dart';
import 'settings_provider.dart';
import 'route_provider.dart';

class _Sentinel {
  const _Sentinel();
}

class TripState {
  final TripLeg? activeLeg;
  final List<TripLeg> todayLegs;

  const TripState({this.activeLeg, this.todayLegs = const []});

  static const _unset = _Sentinel();

  TripState copyWith({Object? activeLeg = _unset, List<TripLeg>? todayLegs}) {
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

  bool _callbacksWired = false;

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

    state = TripState(activeLeg: activeLeg, todayLegs: legs);
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
    LogService().info(
      'Trip: started ${route.name} (odo: $startOdometer, leg #$legOrder)',
    );
    await DatabaseService.updateRouteTimestamp(route.id!);

    final todayLegs = await DatabaseService.getLegsForDate(_today);
    if (!mounted) return saved;

    state = state.copyWith(activeLeg: saved, todayLegs: todayLegs);

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
      'Trip: started ad-hoc from $startLocation (odo: $startOdometer, leg #$legOrder)',
    );

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
    LogService().info(
      'Trip: stopped (odo: $endOdometer, km: ${leg.kmDriven}, returnHome: ${leg.isReturnHome})',
    );
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
      final updatedDayLegs = await _calculator.finalizeAndPersistDay(dayLegs);
      _syncToSheets(updatedDayLegs);
    }

    final todayLegs = await DatabaseService.getLegsForDate(_today);
    if (!mounted) return leg;

    state = state.copyWith(activeLeg: null, todayLegs: todayLegs);

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

  // ── Orchestration seam ───────────────────────────────────────────────

  /// Wire service callbacks so external events (notification taps,
  /// detection triggers) flow through this notifier instead of the screen.
  /// Call once after [BackgroundService.initialize] and
  /// [NotificationService.initialize].
  void initialize() {
    if (_callbacksWired) return;
    _callbacksWired = true;
    _wireCallbacks();

    final detectionService = _ref.read(tripDetectionServiceProvider);
    if (!isDriving) {
      detectionService.start();
    }
  }

  /// Start a trip (route-based or ad-hoc). Stops auto-detection, creates
  /// the leg, starts the background service, and begins GPS live-distance
  /// tracking. Replaces ~60 lines of orchestration in HomeScreen.
  Future<void> startTrip({
    required int startOdometer,
    required String startLocation,
    model.Route? route,
    String? purpose,
    String? driver,
    DateTime? startTime,
  }) async {
    _ref.read(tripDetectionServiceProvider).stop();

    final backgroundService = _ref.read(backgroundServiceProvider);
    backgroundService.updateSettings(_settings);

    TripLeg leg;
    if (route != null) {
      leg = await startDriving(
        route: route,
        startOdometer: startOdometer,
        purpose: purpose ?? '',
        driver: driver,
        startTime: startTime,
      );
      if (route.id != null && purpose != null && purpose.isNotEmpty) {
        await _ref.read(routeProvider.notifier).savePurpose(route.id!, purpose);
      }
      if (route.id != null) {
        await _ref.read(routeProvider.notifier).markUsed(route.id!);
      }
    } else {
      leg = await startAdHocDriving(
        startOdometer: startOdometer,
        startLocation: startLocation,
        purpose: purpose ?? '',
        driver: driver,
        startTime: startTime,
      );
    }

    await backgroundService.onDrivingStarted(leg);
  }

  /// Stop the active trip, showing the arrival dialog first so the user
  /// can confirm / adjust the odometer, end time, location, and purpose.
  /// Replaces the duplicated arrival-dialog flow in ActiveTripCard and
  /// HomeScreen.
  Future<void> stopTrip(BuildContext context) async {
    final active = state.activeLeg;
    if (active == null) return;

    final isAdHoc = active.routeId == null && active.routeDescription == null;
    final expectedOdometer = active.startOdometer + active.kmDriven.toInt();

    List<String> suggestions = const [];
    if (isAdHoc) {
      try {
        suggestions = await DatabaseService.getUniqueLocations();
      } catch (_) {}
    }

    final visionService = _ref.read(odometerVisionServiceProvider);

    final result = await showOdometerDialog(
      context: context,
      title: 'Olen perillä',
      subtitle: isAdHoc
          ? 'Lähtö: ${active.startLocation}'
          : 'Kohde: ${active.endLocation ?? active.routeDescription}',
      label: 'Matkamittari perillä (km)',
      actionLabel: 'Lopeta ajo',
      initialValue: isAdHoc ? null : expectedOdometer,
      expectedHint: isAdHoc ? null : expectedOdometer,
      showTime: true,
      initialTime: DateTime.now(),
      timeLabel: 'Päättymisaika',
      locationLabel: isAdHoc ? 'Määränpää' : null,
      locationSuggestions: suggestions,
      relatedField: isAdHoc ? 'Tarkoitus' : null,
      initialPurpose: isAdHoc ? active.purpose : null,
      visionService: visionService,
    );

    if (result == null) return;

    await stopDriving(
      result.odometer,
      endTime: result.time,
      endLocation: result.location,
      purpose: result.purpose,
    );
    _resetTripState();
  }

  /// Cancel the active trip after a confirmation dialog.
  Future<void> cancelTrip(BuildContext context) async {
    final active = state.activeLeg;
    if (active == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Peru matka'),
        content: const Text(
          'Haluatko varmasti peruuttaa käynnissä olevan matkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Ei'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Peru'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await cancelDriving();
    _resetTripState();
  }

  /// Clean up after a trip ends or is cancelled: stop background service,
  /// stop detection, restart detection.
  void _resetTripState() {
    _ref.read(backgroundServiceProvider).onDrivingStopped();
    final detectionService = _ref.read(tripDetectionServiceProvider);
    detectionService.stop();
    detectionService.start();
  }

  /// Implements the arrival flow for the notification "Olen perillä" action.
  /// Falls back to a fresh DB read when the in-memory state is empty — this
  /// happens on cold-launch from the notification action, where the
  /// flushPendingLaunchAction call fires the callback before HomeScreen's
  /// initial `load()` has populated state.activeLeg. Without the fallback
  /// the action silently no-ops and the leg stays open as a draft with no
  /// recorded end time.
  Future<void> _handleArrival(DateTime arrivedAt) async {
    var active = state.activeLeg;
    if (active == null) {
      active = await DatabaseService.getActiveLeg();
      if (active == null) return;
      if (!mounted) return;
      state = state.copyWith(activeLeg: active);
    }
    final expectedOdometer = active.startOdometer + active.kmDriven.toInt();
    await stopDriving(expectedOdometer, endTime: arrivedAt);
    if (!mounted) return;
    _resetTripState();
  }

  /// Wipes the in-memory TripState without touching the database, so tests
  /// can simulate the cold-launch race where the notification action fires
  /// before `load()` has hydrated state.activeLeg.
  @visibleForTesting
  void clearInMemoryStateForTesting() {
    state = const TripState();
  }

  // ── Service callback wiring ──────────────────────────────────────────

  void _wireCallbacks() {
    final backgroundService = _ref.read(backgroundServiceProvider);
    final detectionService = _ref.read(tripDetectionServiceProvider);
    final ns = _ref.read(notificationServiceProvider);

    backgroundService.onArrived = () {
      // Capture the tap moment up front so a slow DB hydration (cold-launch
      // path) doesn't push the recorded arrival into the future.
      final arrivedAt = DateTime.now();
      unawaited(_handleArrival(arrivedAt));
    };

    backgroundService.onStillDriving = () {
      backgroundService.onStillDrivingPressed();
    };

    detectionService.onStartTripRequested = () {
      final routes = _ref.read(routeProvider);
      if (routes.isNotEmpty) {
        _autoStartWithRoute(routes.first);
      }
    };

    ns.onStartTrip = () {
      detectionService.onStartTripRequested?.call();
    };

    ns.onEndTrip = () {
      if (state.activeLeg != null) {
        backgroundService.onArrived?.call();
      }
    };

    ns.flushPendingLaunchAction();
  }

  Future<void> _autoStartWithRoute(model.Route route) async {
    final lastLeg = await DatabaseService.getLastLeg();
    final initialOdometer = lastLeg?.endOdometer;
    if (initialOdometer == null) return;

    await startTrip(
      startOdometer: initialOdometer,
      startLocation: route.startLocation,
      route: route,
      purpose: route.lastPurpose,
      driver: _settings.driverName,
    );
  }

  Future<void> _saveAdHocRoute(TripLeg leg) async {
    final start = leg.startLocation.trim();
    final end = leg.endLocation!.trim();
    final routeNotifier = _ref.read(routeProvider.notifier);

    final exists = _ref
        .read(routeProvider)
        .any(
          (r) =>
              r.startLocation.trim().toLowerCase() == start.toLowerCase() &&
              r.endLocation.trim().toLowerCase() == end.toLowerCase(),
        );
    if (exists) return;

    final now = DateTime.now();
    await routeNotifier.add(
      model.Route(
        name: '$start → $end',
        startLocation: start,
        endLocation: end,
        distanceKm: leg.kmDriven,
        lastPurpose: (leg.purpose != null && leg.purpose!.isNotEmpty)
            ? leg.purpose
            : null,
        createdAt: now,
        updatedAt: now,
      ),
    );
    LogService().info(
      'Trip: saved ad-hoc route $start -> $end (${leg.kmDriven} km)',
    );
  }

  Future<void> _syncToSheets(List<TripLeg> legs) async {
    final settings = _ref.read(settingsProvider);
    if (settings.sheetId.isEmpty) return;

    try {
      final sheets = _ref.read(sheetsServiceProvider);
      final deletedIds = await DatabaseService.getDeletedLegIds();
      LogService().info(
        'Sheets: syncing ${legs.length} legs to ${settings.sheetTab} (+ ${deletedIds.length} deletes)',
      );
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
      await _calculator.finalizeAndPersistDay(legs);
    }
    await load();
  }

  /// Called when the app is backgrounded. Logged for diagnostics only — the
  /// active trip lives in the database and is re-synced on the next
  /// foreground.
  void onAppBackgrounded() {
    final active = state.activeLeg;
    if (active != null) {
      LogService().info('Trip: app backgrounded with active leg ${active.id}');
    }
  }

  /// Called when the app returns to the foreground.
  ///
  /// Re-syncs from the database so the active-trip card always reflects the
  /// persisted state. The app can be resumed — for example when the user
  /// reopens it from the driving notification — without HomeScreen.initState,
  /// and therefore the startup [load], running again. That leaves the
  /// in-memory [TripState.activeLeg] stale or empty even though the leg is
  /// still open in the DB, which is why the blue active-trip card could go
  /// missing until a full cold restart. The database is the source of truth:
  /// an open leg dated today is still an active trip, so reloading restores
  /// the card. If no trip is active, restart auto-detection.
  Future<void> onAppForegrounded() async {
    await load();
    if (!mounted) return;

    if (!isDriving) {
      _ref.read(tripDetectionServiceProvider).start();
    }
  }

  /// Get today's day summary for display.
  ({
    double totalKm,
    double totalKmAllowance,
    double totalDailyAllowance,
    double grandTotal,
    double totalHours,
    bool estimated,
  })
  get daySummary {
    final legs = state.todayLegs;
    final summary = _calculator.summarizeDay(legs);
    final totalHours = legs.isNotEmpty ? legs.last.legDurationHours : 0.0;

    return (
      totalKm: summary.totalKm,
      totalKmAllowance: summary.totalKmAllowance,
      totalDailyAllowance: summary.totalDailyAllowance,
      grandTotal: summary.grandTotal,
      totalHours: totalHours,
      estimated: summary.estimated,
    );
  }
}

final tripProvider = StateNotifierProvider<TripNotifier, TripState>((ref) {
  return TripNotifier(ref);
});
