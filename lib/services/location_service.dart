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

  Future<bool> hasPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;

    return true;
  }

  /// Find the nearest known location zone within its radius.
  /// Returns null if no zone is within range.
  Future<LocationZone?> findNearestZone(Position position) async {
    final zones = await DatabaseService.getAllLocationZones();
    if (zones.isEmpty) return null;

    LocationZone? nearest;
    double nearestDist = double.infinity;

    for (final zone in zones) {
      final dist = _haversineDistance(
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

    final hasPerm = await hasPermission();
    if (!hasPerm) return;

    _isMonitoring = true;

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 100,
      ),
    ).listen((position) {
      _currentPosition = position;
    });

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
          final dist = _haversineDistance(
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
  static double _haversineDistance(
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
