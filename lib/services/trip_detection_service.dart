import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../models/route.dart' as model;
import '../models/app_settings.dart';
import 'database_service.dart';
import 'location_service.dart';
import 'notification_service.dart';
import 'log_service.dart';

enum DetectionState { idle, monitoring, driving, arrived }

class TripDetectionService {
  final LocationService _locationService;
  final NotificationService _notificationService;

  StreamSubscription<Position>? _positionStream;
  Timer? _speedCheckTimer;
  Timer? _stopCheckTimer;

  DetectionState _state = DetectionState.idle;
  DetectionState get state => _state;

  int _highSpeedSeconds = 0;
  int _lowSpeedSeconds = 0;
  bool _wasDriving = false;

  void Function()? onStartTripRequested;
  void Function()? onEndTripRequested;

  TripDetectionService({
    required LocationService locationService,
    required NotificationService notificationService,
  })  : _locationService = locationService,
        _notificationService = notificationService;

  /// Update app settings (reserved for future configuration).
  void updateSettings(AppSettings settings) {
    // Reserved for future use
  }

  Future<void> start() async {
    if (_state != DetectionState.idle) return;

    final hasPerm = await _locationService.hasPermissionGranted();
    if (!hasPerm) {
      LogService().info('TripDetection: no location permission, skipping');
      return;
    }

    _state = DetectionState.monitoring;
    _highSpeedSeconds = 0;
    _lowSpeedSeconds = 0;
    _wasDriving = false;

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 50,
        timeLimit: Duration(seconds: 30),
      ),
    ).listen(_onPosition);

    _speedCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkDrivingState();
    });

    LogService().info('TripDetection: started monitoring');
  }

  Future<void> stop() async {
    _state = DetectionState.idle;
    await _positionStream?.cancel();
    _positionStream = null;
    _speedCheckTimer?.cancel();
    _speedCheckTimer = null;
    _stopCheckTimer?.cancel();
    _stopCheckTimer = null;
    _highSpeedSeconds = 0;
    _lowSpeedSeconds = 0;
    LogService().info('TripDetection: stopped');
  }

  void resetAfterTripStart() {
    _state = DetectionState.driving;
    _highSpeedSeconds = 0;
    _lowSpeedSeconds = 0;
    _stopCheckTimer?.cancel();
    _stopCheckTimer = null;
    LogService().info('TripDetection: trip started, now monitoring arrival');
  }

  void _onPosition(Position position) {
    if (position.speed >= 5.0) {
      _highSpeedSeconds += 10; // ~10s between updates with 30s timeLimit
      _lowSpeedSeconds = 0;
    } else if (position.speed < 1.0 && _state == DetectionState.driving) {
      _lowSpeedSeconds += 10;
    } else {
      // Between 1-5 m/s: reset low speed counter but don't count high
      _lowSpeedSeconds = 0;
    }
  }

  void _checkDrivingState() {
    switch (_state) {
      case DetectionState.monitoring:
        if (_highSpeedSeconds >= 30) {
          _onDrivingDetected();
        }
        break;

      case DetectionState.driving:
        if (_lowSpeedSeconds >= 60 && _wasDriving) {
          _onArrivedDetected();
        }
        break;

      default:
        break;
    }
  }

  void _onDrivingDetected() {
    _state = DetectionState.driving;
    _wasDriving = true;
    LogService().info('TripDetection: driving detected');

    _notificationService.showTripDetectionNotification();
  }

  void _onArrivedDetected() {
    _state = DetectionState.arrived;
    _wasDriving = false;
    _highSpeedSeconds = 0;
    _lowSpeedSeconds = 0;
    LogService().info('TripDetection: arrival detected');

    _notificationService.showTripEndDetectionNotification();
  }

  /// Auto-detect the best route for the current trip based on start/end locations.
  /// Returns null if no matching route found.
  Future<model.Route?> suggestRoute({
    required String startLocation,
    required String endLocation,
  }) async {
    final routes = await DatabaseService.getAllRoutes();
    if (routes.isEmpty) return null;

    final startLower = startLocation.trim().toLowerCase();
    final endLower = endLocation.trim().toLowerCase();

    // Exact match
    for (final route in routes) {
      if (route.startLocation.trim().toLowerCase() == startLower &&
          route.endLocation.trim().toLowerCase() == endLower) {
        return route;
      }
    }

    // Partial match: start matches
    for (final route in routes) {
      if (route.startLocation.trim().toLowerCase() == startLower) {
        return route;
      }
    }

    // Default: most recently used
    return routes.isNotEmpty ? routes.first : null;
  }

  void dispose() {
    stop();
  }
}
