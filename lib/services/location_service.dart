import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../models/app_settings.dart';
import 'notification_service.dart';

class LocationService {
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;

  bool _isMonitoring = false;
  Timer? _proximityTimer;
  String? _targetLocation;

  bool get isMonitoring => _isMonitoring;

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
        intervalDuration: Duration(seconds: 15),
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

      final distance = await _calculateCrowDistanceToHome(homeLocation);
      if (distance != null && distance < 0.5) {
        await notificationService.showArrivalReminder(_targetLocation!);
      }
    });
  }

  Future<double?> _calculateCrowDistanceToHome(
      String homeLocation) async {
    return null;
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
}
