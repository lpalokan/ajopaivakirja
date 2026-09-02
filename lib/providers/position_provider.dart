import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../main.dart';
import '../services/location_service.dart';

/// Why the home screen is showing (or not showing) a place name.
enum PositionStatus {
  /// A fix has been asked for and nothing has come back yet.
  searching,

  /// We have a fix and it lands on a known location.
  atKnownLocation,

  /// We have a fix, but no known location is within
  /// [LocationService.nearbyMatchRadiusMeters] of it.
  unknownPlace,

  /// The OS has not granted location access, so there is nothing to show.
  noPermission,

  /// Permission is granted but no fix arrived.
  noFix,
}

/// Where the driver is right now, as one value the whole home screen reads.
///
/// Position used to live inside LocationChip's State, resolved once in
/// `initState` and never again — which is why the chip showed where you were
/// when the app was opened. Owning it here means it can be refreshed on
/// resume, followed live, and reused by the nearby-route list.
class CurrentPositionState {
  final Position? position;

  /// Known locations within reach of [position], nearest first.
  final List<ZoneMatch> nearbyZones;
  final PositionStatus status;
  final DateTime? updatedAt;

  const CurrentPositionState({
    this.position,
    this.nearbyZones = const [],
    this.status = PositionStatus.searching,
    this.updatedAt,
  });

  /// The name of the closest known location, or null when we cannot name
  /// where we are.
  String? get placeName =>
      nearbyZones.isEmpty ? null : nearbyZones.first.zone.name;

  double? get distanceMeters =>
      nearbyZones.isEmpty ? null : nearbyZones.first.distanceMeters;
}

class CurrentPositionNotifier extends StateNotifier<CurrentPositionState> {
  CurrentPositionNotifier(this._service) : super(const CurrentPositionState()) {
    // Fixes produced by an active trip's stream. Costs nothing while no trip
    // is running (the controller simply stays quiet), and means the chip
    // keeps updating mid-drive without a second GPS subscription.
    _tripFixes = _service.positionStream.listen(_onPosition);
  }

  final LocationService _service;
  StreamSubscription<Position>? _tripFixes;
  StreamSubscription<Position>? _idleFixes;
  bool _resolving = false;

  /// Whether anyone is looking at the screen. Tracked explicitly rather than
  /// inferred, because the idle watch is started from async paths that can
  /// finish long after the app has gone away — see [startIdleWatch].
  bool _foreground = true;

  /// Re-resolve from scratch: the platform's cached fix first so the screen
  /// has something immediately, then a real one.
  Future<void> refresh() async {
    if (_resolving) return;
    _resolving = true;
    try {
      if (!await _service.hasPermissionGranted()) {
        if (mounted) {
          state = CurrentPositionState(
            position: state.position,
            nearbyZones: state.nearbyZones,
            status: PositionStatus.noPermission,
            updatedAt: state.updatedAt,
          );
        }
        return;
      }

      if (state.position == null) {
        final cached = await _service.getLastKnownPosition();
        if (cached != null) await _onPosition(cached);
      }

      final fresh = await _service.getCurrentPosition();
      if (fresh != null) {
        await _onPosition(fresh);
      } else if (mounted && state.position == null) {
        state = const CurrentPositionState(status: PositionStatus.noFix);
      }
    } finally {
      _resolving = false;
    }
  }

  /// Follow the driver while the home screen is open and no trip is running.
  /// Idempotent, so lifecycle callbacks can call it freely.
  ///
  /// Two hard preconditions, both learned from a day's battery (issue #91):
  ///
  /// * **The app must be in the foreground.** This is called from async
  ///   paths that routinely finish after the app has gone away — the trip
  ///   state settling at the end of an arrival is the one that bit us. A
  ///   watch started then is never stopped, because [stopIdleWatch] only
  ///   runs on the *next* pause and there isn't one, so it holds a location
  ///   request open for the life of the process.
  /// * **No trip stream may be open.** `geolocator` caches one position
  ///   stream per process: a second `getPositionStream` returns the first
  ///   one and discards the [LocationSettings] handed to it, and the
  ///   platform request is dropped only when that stream's LAST listener
  ///   cancels. Subscribing here mid-trip therefore does not open a cheap
  ///   watch at all — it attaches to the trip's foreground-service,
  ///   wake-locked, high-accuracy request and keeps it running afterwards.
  ///   Whoever tears the trip down calls this again when it is safe.
  void startIdleWatch() {
    if (_idleFixes != null) return;
    if (!_foreground) return;
    if (_service.isMonitoring) return;
    _idleFixes = _service.watchIdlePosition().listen(_onPosition);
  }

  /// Stop following. Called when the app is backgrounded (nobody is looking)
  /// and while a trip runs (the trip's own stream takes over).
  void stopIdleWatch() {
    _idleFixes?.cancel();
    _idleFixes = null;
  }

  /// The app went away. Drops the watch and — the part that matters —
  /// remembers that it did, so a late async caller cannot put it back.
  void onAppBackgrounded() {
    _foreground = false;
    stopIdleWatch();
  }

  /// The app is on screen again, so following the driver is worth paying
  /// for. Does not start the watch itself: the caller decides, because a
  /// resume with a trip already running must leave the trip's stream alone.
  void onAppForegrounded() {
    _foreground = true;
  }

  /// Re-match the current fix against the zone table. Called after a zone is
  /// added or learned, so the screen reflects it without waiting for the next
  /// GPS fix.
  Future<void> rematch() async {
    final pos = state.position;
    if (pos != null) await _onPosition(pos);
  }

  Future<void> _onPosition(Position position) async {
    final matches = await _service.findNearbyZones(position);
    if (!mounted) return;
    state = CurrentPositionState(
      position: position,
      nearbyZones: matches,
      status: matches.isEmpty
          ? PositionStatus.unknownPlace
          : PositionStatus.atKnownLocation,
      updatedAt: DateTime.now(),
    );
  }

  @override
  void dispose() {
    _tripFixes?.cancel();
    _idleFixes?.cancel();
    super.dispose();
  }
}

final currentPositionProvider =
    StateNotifierProvider<CurrentPositionNotifier, CurrentPositionState>((ref) {
      return CurrentPositionNotifier(ref.watch(locationServiceProvider));
    });
