import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../models/route.dart' as model;
import '../models/app_settings.dart';
import 'database_service.dart';
import 'driving_detector.dart';
import 'location_service.dart';
import 'notification_service.dart';
import 'log_service.dart';

export 'driving_detector.dart' show DetectionState;

/// Platform adapter around the pure [DrivingDetector]: wires the Geolocator
/// position stream and a periodic timer to the state machine, and turns the
/// machine's transition events into notifications. All detection *logic* lives
/// in [DrivingDetector]; this class only does the IO.
class TripDetectionService {
  final LocationService _locationService;
  final NotificationService _notificationService;
  final DrivingDetector _detector;

  StreamSubscription<Position>? _positionStream;
  Timer? _speedCheckTimer;

  DetectionState get state => _detector.state;

  void Function()? onStartTripRequested;
  void Function()? onEndTripRequested;

  TripDetectionService({
    required LocationService locationService,
    required NotificationService notificationService,
    DetectionConfig config = const DetectionConfig(),
  })  : _locationService = locationService,
        _notificationService = notificationService,
        _detector = DrivingDetector(config: config);

  /// Apply the user's auto-detection thresholds (Settings → Ajontunnistus).
  ///
  /// Safe to call at any time, including mid-monitoring: the detector keeps
  /// its counters in seconds, so the new thresholds are simply what the next
  /// check cycle measures against.
  void updateSettings(AppSettings settings) {
    final next = detectionConfigFrom(settings);
    if (next.highSpeed == _detector.config.highSpeed &&
        next.drivingAfterSeconds == _detector.config.drivingAfterSeconds &&
        next.arrivedAfterSeconds == _detector.config.arrivedAfterSeconds) {
      return;
    }
    _detector.updateConfig(next);
    LogService().info(
      'TripDetection: thresholds updated — '
      '${next.highSpeed} m/s for ${next.drivingAfterSeconds}s, '
      'arrival after ${next.arrivedAfterSeconds}s',
    );
  }

  /// Build detector thresholds from the persisted app settings, keeping the
  /// fixed sampling cadence (the counters advance in real seconds, so this is
  /// a property of the position feed rather than of the user's preference).
  static DetectionConfig detectionConfigFrom(AppSettings settings) =>
      DetectionConfig(
        highSpeed: AppSettings.clampDetectionSpeed(settings.detectionSpeedMps),
        drivingAfterSeconds: AppSettings.clampDetectionDrivingSeconds(
          settings.detectionDrivingSeconds,
        ),
        arrivedAfterSeconds: AppSettings.clampDetectionArrivalSeconds(
          settings.detectionArrivalSeconds,
        ),
      );

  Future<void> start() async {
    if (_detector.state != DetectionState.idle) return;

    final hasPerm = await _locationService.hasPermissionGranted();
    if (!hasPerm) {
      LogService().info('TripDetection: no location permission, skipping');
      return;
    }

    _detector.startMonitoring();

    // No timeLimit: a stationary device produces no updates, and a
    // timeLimit makes the stream throw TimeoutException every time that
    // happens. onError tears monitoring down cleanly instead of leaking
    // an unhandled async error.
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 50,
      ),
    ).listen(
      (p) => _detector.onSample(p.speed),
      onError: (Object e) {
        LogService().info('TripDetection: position stream error: $e');
        stop();
      },
      cancelOnError: true,
    );

    _speedCheckTimer = Timer.periodic(
      Duration(seconds: _detector.config.sampleIntervalSeconds),
      (_) => _onTick(),
    );

    LogService().info(
      'TripDetection: started monitoring (${_detector.config.highSpeed} m/s '
      'for ${_detector.config.drivingAfterSeconds}s, arrival after '
      '${_detector.config.arrivedAfterSeconds}s)',
    );
  }

  Future<void> stop() async {
    _detector.reset();
    await _positionStream?.cancel();
    _positionStream = null;
    _speedCheckTimer?.cancel();
    _speedCheckTimer = null;
    LogService().info('TripDetection: stopped');
  }

  void resetAfterTripStart() {
    _detector.markTripStarted();
    LogService().info('TripDetection: trip started, now monitoring arrival');
  }

  void _onTick() {
    switch (_detector.tick()) {
      case DetectionEvent.drivingDetected:
        LogService().info('TripDetection: driving detected');
        _notificationService.showTripDetectionNotification();
        break;
      case DetectionEvent.arrivedDetected:
        LogService().info('TripDetection: arrival detected');
        _notificationService.showTripEndDetectionNotification();
        break;
      case null:
        break;
    }
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
