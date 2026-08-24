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
  void startIdleWatch() {
    if (_idleFixes != null) return;
    _idleFixes = _service.watchIdlePosition().listen(_onPosition);
  }

  /// Stop following. Called when the app is backgrounded (nobody is looking)
  /// and while a trip runs (the trip's own stream takes over).
  void stopIdleWatch() {
    _idleFixes?.cancel();
    _idleFixes = null;
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
