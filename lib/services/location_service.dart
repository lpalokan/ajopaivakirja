import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import '../models/app_settings.dart';
import '../models/location_zone.dart';
import 'notification_service.dart';
import 'database_service.dart';

class LocationService {
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;

  // At most one native permission dialog per session: concurrent callers
  // share the in-flight request, and once the user has answered we never
  // auto-prompt again (which previously stacked dialogs permanently).
  bool _permissionRequested = false;
  Future<bool>? _pendingPermission;

  bool _isMonitoring = false;
  Timer? _proximityTimer;
  String? _targetLocation;

  bool get isMonitoring => _isMonitoring;

  /// Get current GPS position (one-shot).
  Future<Position?> getCurrentPosition() async {
    try {
      _currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      return _currentPosition;
    } catch (_) {
      return null;
    }
  }

  /// Check whether location permission is already granted. Never shows a
  /// dialog — use this from automatic/startup paths so the app does not
  /// prompt on its own (which made the dialog reappear endlessly).
  Future<bool> hasPermissionGranted() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  /// Check permission and, only if the user has not yet been asked this
  /// session, show the OS dialog exactly once. Call this only in response
  /// to an explicit user action that needs location.
  Future<bool> hasPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      return true;
    }
    if (permission == LocationPermission.deniedForever) return false;

    // Permission is `denied`. Ask the OS exactly once per session; if a
    // request is already on screen, await that same one instead of
    // spawning another dialog on top of it.
    if (_permissionRequested) return false;
    _pendingPermission ??= _requestPermissionOnce();
    return _pendingPermission!;
  }

  Future<bool> _requestPermissionOnce() async {
    _permissionRequested = true;
    final permission = await Geolocator.requestPermission();
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  /// Find the nearest known location zone within its radius.
  /// Returns null if no zone is within range.
  Future<LocationZone?> findNearestZone(Position position) async {
    final zones = await DatabaseService.getAllLocationZones();
    if (zones.isEmpty) return null;

    LocationZone? nearest;
    double nearestDist = double.infinity;

    for (final zone in zones) {
      final dist = haversineDistance(
        position.latitude, position.longitude,
        zone.latitude, zone.longitude,
      );
      if (dist <= zone.radiusMeters && dist < nearestDist) {
        nearest = zone;
        nearestDist = dist;
      }
    }

    return nearest;
  }

  /// Get the best location name for the current GPS position.
  /// Returns null if no zone matches.
  Future<String?> getLocationName(Position position) async {
    final zone = await findNearestZone(position);
    return zone?.name;
  }

  Future<void> startMonitoringDestination(
    String destinationName,
    AppSettings settings,
    NotificationService notificationService,
  ) async {
    if (_isMonitoring) await stopMonitoring();

    _targetLocation = destinationName;

    final hasPerm = await hasPermissionGranted();
    if (!hasPerm) return;

    _isMonitoring = true;

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 100,
      ),
    ).listen(
      (position) {
        _currentPosition = position;
      },
      onError: (Object _) {
        // A transient location error must not leak as an unhandled
        // async error; monitoring simply pauses until the next fix.
      },
      cancelOnError: false,
    );

    _proximityTimer =
        Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!_isMonitoring || _targetLocation == null) return;

      final pos = _currentPosition;
      if (pos == null) return;

      final homeLocation = settings.homeLocation.trim().toLowerCase();
      final target = _targetLocation!.trim().toLowerCase();

      if (target != homeLocation) return;

      // Check if we're near the home zone
      final zones = await DatabaseService.getAllLocationZones();
      bool nearHome = false;
      for (final zone in zones) {
        if (zone.name.trim().toLowerCase() == homeLocation) {
          final dist = haversineDistance(
            pos.latitude, pos.longitude,
            zone.latitude, zone.longitude,
          );
          if (dist <= zone.radiusMeters + 200) { // a bit of grace
            nearHome = true;
            break;
          }
        }
      }

      if (nearHome) {
        await notificationService.showArrivalReminder(_targetLocation!);
      }
    });
  }

  Future<void> stopMonitoring() async {
    _isMonitoring = false;
    _targetLocation = null;
    _proximityTimer?.cancel();
    _proximityTimer = null;
    await _positionStream?.cancel();
    _positionStream = null;
  }

  void dispose() {
    stopMonitoring();
  }

  /// Haversine distance in meters between two lat/lon points.
  static double haversineDistance(
    double lat1, double lon1, double lat2, double lon2,
  ) {
    const double earthRadius = 6371000;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRadians(double degrees) => degrees * pi / 180.0;
}
