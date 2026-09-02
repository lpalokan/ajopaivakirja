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
import '../services/bluetooth_trigger_service.dart';
import '../services/database_service.dart';
import '../services/sheets_sync.dart';
import '../services/trip_calculator.dart';
import '../services/location_service.dart';
import '../services/log_service.dart';
import '../widgets/odometer_dialog.dart';
import '../main.dart';
import 'position_provider.dart';
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

  /// Presenter the UI registers (see [setArrivalPresenter]) so a
  /// notification-triggered arrival can show the arrival dialog on the live
  /// screen. Null until HomeScreen wires it — or while no screen is mounted —
  /// in which case arrival falls back to recording the estimated odometer so
  /// the leg is never left open.
  Future<void> Function()? _arrivalPresenter;

  /// Its start-of-drive counterpart, for the car reminder's
  /// "Kirjaa lähtömittari" button. See [setStartPresenter].
  Future<void> Function()? _startPresenter;

  TripNotifier(this._ref) : super(const TripState());

  AppSettings get _settings => _ref.read(settingsProvider);

  TripCalculator get _calculator =>
      TripCalculator(_settings, kmRates: _kmRates);

  Future<void> loadKmRates() async {
    _kmRates = await DatabaseService.getAllKmRates();
  }

  String get _today => DateFormat('yyyy-MM-dd').format(DateTime.now());

  bool get isDriving => state.activeLeg != null;

  /// What the native car-Bluetooth receiver was last told. Null until the
  /// first [load], so the launch mirror always goes out.
  bool? _mirroredTripActive;

  /// Every path that opens or closes a leg — start, ad-hoc start, arrival,
  /// cancel, the cold-launch hydration in [_promptArrival] — ends in an
  /// assignment here, so mirroring from the setter is the one place that
  /// cannot be forgotten when a new path is added.
  @override
  set state(TripState value) {
    super.state = value;
    _mirrorTripState(value.activeLeg != null);
  }

  /// Push "a trip is / is not open" to [BluetoothTriggerService], which is
  /// what the native receiver reads when the car's Bluetooth connects or
  /// disconnects. Without it the car would prompt "Aloititko ajon?" at a
  /// driver who has already started, and "Päättyikö ajo?" when there is
  /// nothing to end.
  ///
  /// Best-effort and never awaited: a trip must not fail, or wait, because a
  /// reminder flag could not be written. Unchanged values are skipped, so the
  /// steady stream of [TripState] updates costs nothing.
  void _mirrorTripState(bool active) {
    if (!mounted || _mirroredTripActive == active) return;
    _mirroredTripActive = active;
    unawaited(_ref.read(bluetoothTriggerServiceProvider).setTripActive(active));
  }

  Future<void> load() async {
    final legs = await DatabaseService.getLegsForDate(_today);
    final activeLeg = await DatabaseService.getActiveLeg();
    if (!mounted) return;

    // Forget what the native side was last told so the assignment below
    // re-asserts it: the app can be killed mid-trip, and the stored flag is
    // then whatever it was when the process died.
    _mirroredTripActive = null;
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

    // We are standing at the destination right now — the one moment its
    // name and its coordinates are both known. Unawaited: it may need a
    // fresh fix, and arrival must not wait on the GPS chip.
    unawaited(_rememberPlace(leg.endLocation));

    // Persist an ad-hoc journey as a reusable route (also makes its start
    // and end locations available as suggestions next time).
    if (wasAdHoc &&
        leg.endLocation != null &&
        leg.endLocation!.isNotEmpty &&
        leg.startLocation.isNotEmpty) {
      await _saveAdHocRoute(leg);
    }

    if (leg.isReturnHome) {
      // The työmatka being finalized may have started days ago: päivärahat
      // are counted in 24-hour travel days from departure, so finalizing
      // only today's legs paid nothing for an overnight trip and nothing at
      // all for the day it left on.
      final tripLegs = await _tripLegsEndingWith(leg);
      LogService().info(
        'Trip: finalizing työmatka of ${tripLegs.length} leg(s) from '
        '${tripLegs.first.date} to ${leg.date}',
      );
      final updatedTripLegs = await _calculator.finalizeAndPersistTrip(
        tripLegs,
      );
      _syncToSheets(updatedTripLegs);
    }

    final todayLegs = await DatabaseService.getLegsForDate(_today);
    if (!mounted) return leg;

    state = state.copyWith(activeLeg: null, todayLegs: todayLegs);

    return leg;
  }

  /// The legs of the työmatka ending with [last], back to the departure from
  /// home. Looks 30 days back — far enough for any real trip, bounded so a
  /// history with no departure-from-home can't drag in everything.
  Future<List<TripLeg>> _tripLegsEndingWith(TripLeg last) async {
    final from = DateTime.now().subtract(const Duration(days: 30));
    final fromDate =
        '${from.year.toString().padLeft(4, '0')}-'
        '${from.month.toString().padLeft(2, '0')}-'
        '${from.day.toString().padLeft(2, '0')}';
    final candidates = await DatabaseService.getLegsFrom(fromDate);
    return TripCalculator.tripLegsEndingWith(
      candidates,
      last,
      _settings.homeLocation,
    );
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
  }

  /// Registered by HomeScreen so the notification "Olen perillä" action can
  /// present the arrival dialog (mileage + end time) on the live screen,
  /// mirroring the in-app button. Pass null to drop a torn-down screen's
  /// context.
  void setArrivalPresenter(Future<void> Function()? presenter) {
    _arrivalPresenter = presenter;
  }

  /// Registered by HomeScreen so the car reminder's "Kirjaa lähtömittari"
  /// can present the start dialog (mileage) on the live screen. Pass null to
  /// drop a torn-down screen's context.
  void setStartPresenter(Future<void> Function()? presenter) {
    _startPresenter = presenter;
  }

  /// Act on a mileage button tapped on one of the car's Bluetooth reminders.
  ///
  /// Those prompts fire when the car connects or disconnects — the one
  /// moment the odometer is actually in front of the driver — so the button
  /// goes straight to the number instead of dropping them on the home screen
  /// to find it. The tap reaches the app as an Activity intent extra rather
  /// than a notification response: the reminder is posted by native code
  /// with, usually, no Flutter engine in existence, so there is nothing on
  /// the Dart side to receive a response. Consumed rather than read, so a
  /// tap that cold-launched the app fires once and not again on every later
  /// resume.
  ///
  /// Each action is dropped when it asks for something already done — the
  /// driver may well have acted in the app between the ignition and picking
  /// the phone up, and a dialog for a trip that is already closed is worse
  /// than no dialog at all.
  Future<void> consumeCarReminderAction() async {
    final action = await _ref
        .read(bluetoothTriggerServiceProvider)
        .consumePendingAction();
    if (action == null || !mounted) return;
    LogService().info('Bluetooth: car reminder action $action');

    switch (action) {
      case BluetoothTriggerService.logEndAction:
        if (state.activeLeg == null) return;
        await _arrivalPresenter?.call();
      case BluetoothTriggerService.logStartAction:
        if (state.activeLeg != null) return;
        await _startPresenter?.call();
    }
  }

  /// Start a trip (route-based or ad-hoc). Stops auto-detection, creates
  /// the leg, starts the background service, and begins GPS live-distance
  /// tracking. Replaces ~60 lines of orchestration in HomeScreen.
  /// [startLocationConfirmed] says whether [startLocation] is a place the
  /// driver asserted — the location chip resolved it from GPS, or they set it
  /// by hand — rather than one the app guessed. Only an asserted name is
  /// worth remembering; see [_rememberPlace].
  Future<void> startTrip({
    required int startOdometer,
    required String startLocation,
    model.Route? route,
    String? purpose,
    String? driver,
    DateTime? startTime,
    bool startLocationConfirmed = false,
  }) async {
    final backgroundService = _ref.read(backgroundServiceProvider);

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

    // The departure point, but only when the driver actually told us where
    // they are. Two names must never be learned here: the chip's fallback
    // label (the configured home behind "(edellinen)") is the app's own
    // guess, and a route's start location is its assumption about where the
    // driver is standing — start "Töihin" from a customer's yard and it
    // would pin "Koti" to that yard. A learned place sticks, so a wrong one
    // is worse than none.
    if (startLocationConfirmed) unawaited(_rememberPlace(startLocation));

    await backgroundService.onDrivingStarted(leg);
  }

  /// Learn [name] as a known location at the current GPS position, so the
  /// home screen can recognise the place — and offer the routes that start
  /// there — the next time the driver is here.
  ///
  /// Best-effort by design: no fix, no name, or a name the user already has a
  /// zone for and nothing happens. A trip must never fail over bookkeeping,
  /// so it is never awaited.
  Future<void> _rememberPlace(String? name) async {
    if (name == null || name.trim().isEmpty) return;
    final service = _ref.read(locationServiceProvider);
    try {
      var position = _ref.read(currentPositionProvider).position;
      // The idle watch runs on medium accuracy to stay cheap, which is fine
      // for naming a place we already know but too coarse to *place* one: a
      // 200 m zone centred on a 300 m-accurate fix would name the wrong
      // spot for as long as the zone exists. Starting or ending a trip is
      // rare enough to pay for one precise fix.
      if (position == null ||
          position.accuracy > LocationService.learnAccuracyLimitMeters) {
        position =
            await service.getCurrentPosition(
              timeLimit: const Duration(seconds: 8),
            ) ??
            position;
      }
      if (position == null || !mounted) return;

      final learned = await service.rememberPlace(name, position);
      if (learned != null && mounted) {
        await _ref.read(currentPositionProvider.notifier).rematch();
      }
    } catch (e) {
      LogService().warn('GPS: could not remember "$name": $e');
    }
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

    // Free driving ends wherever the driver happens to be, and GPS has
    // already worked out whether that is somewhere they know. Offering the
    // name saves them typing it; it is only an offer, and what they type
    // wins.
    final arrivedAt = isAdHoc
        ? _ref.read(currentPositionProvider).placeName
        : null;

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
      initialLocation: arrivedAt,
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

  /// Clean up after a trip ends or is cancelled: tear the background
  /// service's sensors down, then hand the home screen back its cheap
  /// position watch.
  ///
  /// The order is the whole point. By the time this runs the leg is already
  /// closed, so HomeScreen's trip-state listener has already tried to start
  /// the idle watch and been refused — the trip's position stream is still
  /// open, and `geolocator` would have handed that watch the trip's own
  /// platform request (foreground service, wake lock, high accuracy) instead
  /// of a cheap one, then kept it alive for as long as the process lived
  /// (issue #91). Starting the watch here, after `onDrivingStopped` has
  /// actually closed the trip stream, is what makes it cheap again.
  void _resetTripState() {
    unawaited(() async {
      await _ref.read(backgroundServiceProvider).onDrivingStopped();
      if (!mounted) return;
      _ref.read(currentPositionProvider.notifier).startIdleWatch();
    }());
  }

  /// Implements the arrival flow for the notification "Olen perillä" action.
  /// Brings up the arrival dialog (mileage + end time, time pre-populated) on
  /// the live screen so the user confirms the reading — the same dialog as the
  /// in-app "Olen perillä" button, via the presenter HomeScreen registers in
  /// [setArrivalPresenter]. The dialog records the time and mileage and stops
  /// the trip on save; cancelling leaves the trip active.
  ///
  /// Falls back to a fresh DB read when the in-memory state is empty — this
  /// happens on cold-launch from the notification action, where
  /// flushPendingLaunchAction fires the callback before HomeScreen's initial
  /// `load()` has populated state.activeLeg. If no presenter is registered (no
  /// live UI yet), records the estimated odometer so the leg isn't left open
  /// as a draft with no end time.
  Future<void> _promptArrival(DateTime arrivedAt) async {
    var active = state.activeLeg;
    if (active == null) {
      active = await DatabaseService.getActiveLeg();
      if (active == null) return;
      if (!mounted) return;
      state = state.copyWith(activeLeg: active);
    }

    final presenter = _arrivalPresenter;
    if (presenter != null) {
      await presenter();
      return;
    }

    // No live UI to host the dialog (e.g. cold launch before the first
    // frame). Record the estimated odometer so the leg isn't left open.
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
    final ns = _ref.read(notificationServiceProvider);

    backgroundService.onArrived = () {
      // Capture the tap moment up front so a slow DB hydration (cold-launch
      // path) doesn't push the recorded arrival into the future.
      final arrivedAt = DateTime.now();
      unawaited(_promptArrival(arrivedAt));
    };

    backgroundService.onStillDriving = () {
      backgroundService.onStillDrivingPressed();
    };

    ns.flushPendingLaunchAction();
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
    final sheets = _ref.read(sheetsServiceProvider);
    if (!await sheets.isSignedIn) {
      // Nothing to do until the driver signs in from Settings. Stays silent:
      // this is the automatic day-close path, and the History screen's
      // "n synkronoimatta" chip already surfaces the backlog.
      LogService().info('Sheets: not signed in, skipping automatic sync');
      return;
    }

    try {
      final settings = _ref.read(settingsProvider);
      final plan = await prepareSheetsSync(
        sheets: sheets,
        sheetId: settings.sheetId,
        sheetTab: settings.sheetTab,
        legs: legs,
        persistSheetId: (id) =>
            _ref.read(settingsProvider.notifier).update({'sheet_id': id}),
      );
      LogService().info(
        'Sheets: syncing ${plan.legs.length} legs to ${settings.sheetTab} '
        '(+ ${plan.deletedLegIds.length} deletes)',
      );
      await sheets.appendLegs(
        plan.legs,
        sheetId: plan.target.id,
        sheetTab: settings.sheetTab,
        deletedLegIds: plan.deletedLegIds,
        allowanceDays: await DatabaseService.getAllowanceDaysWithoutLegs(),
        onSynced: (legId) => DatabaseService.markLegSynced(legId),
      );
      if (plan.deletedLegIds.isNotEmpty) {
        await DatabaseService.clearDeletedLegIds(plan.deletedLegIds);
      }
      LogService().info('Sheets: sync complete (${plan.legs.length} legs)');
    } catch (e, st) {
      LogService().error('Sheets: sync failed', e, st);
    }
  }

  Future<void> finalizeDay() async {
    await _calculator.refinalizeAroundDate(_today);
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
  /// the card.
  Future<void> onAppForegrounded() async {
    await load();
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
