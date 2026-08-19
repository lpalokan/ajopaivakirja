import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/app_settings.dart';
import '../models/location_zone.dart';
import 'database_service.dart';
import 'log_service.dart';

class LocationService {
  /// How far the device must move before the trip position stream emits
  /// another fix. At motorway speed this is a fix every few seconds — often
  /// enough to keep the reminder's movement signal fresh, sparse enough that
  /// the GPS chip is not queried continuously.
  static const int tripDistanceFilterMeters = 50;

  /// Minimum gap between "GPS: fix" heartbeat log lines. The log is the only
  /// way to tell, from a drive shared through Settings → Virheloki, whether
  /// fixes kept arriving once the screen was locked — but one line per fix
  /// would flood it, so the heartbeat is throttled to one a minute.
  static const Duration gpsHeartbeatInterval = Duration(minutes: 1);

  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  DateTime? _lastHeartbeatAt;

  /// Broadcast stream of GPS positions for live distance tracking.
  /// Consumers (e.g. ActiveTripCard) subscribe to this for updates.
  final StreamController<Position> _positionController =
      StreamController<Position>.broadcast();

  Stream<Position> get positionStream => _positionController.stream;

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
        position.latitude,
        position.longitude,
        zone.latitude,
        zone.longitude,
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

  /// Location settings for the position stream that runs for the duration of
  /// an active trip.
  ///
  /// On Android this asks geolocator to run its own **location foreground
  /// service** (`GeolocatorLocationService`, declared with
  /// `foregroundServiceType="location"` by the plugin). That is the whole
  /// point: without a foreground service Android stops delivering location to
  /// a `whileInUse` app the moment it leaves the foreground — which is what
  /// users do on every real drive when they lock the screen — and with it the
  /// reminder's movement signal went stale within minutes and "Oletko
  /// perillä?" fired mid-drive (issue #77). With the service running, fixes
  /// keep arriving with the screen locked and `whileInUse` permission is
  /// sufficient; no "Allow all the time" prompt is needed.
  ///
  /// [android] defaults to the running platform and exists so the Android
  /// branch is testable on the host VM.
  static LocationSettings tripLocationSettings({bool? android}) {
    final isAndroid = android ?? (!kIsWeb && Platform.isAndroid);
    if (!isAndroid) {
      return const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: tripDistanceFilterMeters,
      );
    }
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: tripDistanceFilterMeters,
      // Without a wake lock the system can sleep and deliver a burst of
      // positions on wake — useless for a recency check that has to answer
      // "is the vehicle moving right now?".
      // Deliberately NOT worded like the app's own "Ajo käynnissä" driving
      // notification: both are visible for the duration of a trip, and two
      // notifications with the same title read as a bug.
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Ajon sijaintiseuranta',
        notificationText: 'Sijaintia seurataan ajon ajan',
        notificationChannelName: 'Ajon sijaintiseuranta',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
  }

  /// Whether [settings] will make the platform run location updates under a
  /// foreground service.
  static bool isForegroundBacked(LocationSettings settings) =>
      settings is AndroidSettings &&
      settings.foregroundNotificationConfig != null;

  /// Opens the platform position stream for an active trip. Overridden in
  /// tests so the trip-tracking wiring can be exercised without Geolocator.
  @protected
  @visibleForOverriding
  Stream<Position> openTripPositionStream(LocationSettings settings) =>
      Geolocator.getPositionStream(locationSettings: settings);

  /// Best-effort permission name for the trip-start log line. The level the
  /// OS actually granted (`whileInUse` vs `always`) is the first thing to
  /// check in a shared drive log, but it must never be able to break trip
  /// tracking — hence the catch.
  Future<String> _permissionLabel() async {
    try {
      return (await Geolocator.checkPermission()).name;
    } catch (_) {
      return 'unavailable';
    }
  }

  /// One throttled log line per minute while fixes keep arriving. On a shared
  /// drive log, a gap in these lines right after "app backgrounded" is the
  /// signature of location delivery dying at screen-lock.
  void _logHeartbeat(Position position) {
    final now = DateTime.now();
    final last = _lastHeartbeatAt;
    if (last != null && now.difference(last) < gpsHeartbeatInterval) return;
    _lastHeartbeatAt = now;
    LogService().info(
      'GPS: fix speed=${position.speed.toStringAsFixed(1)} m/s '
      '(${(position.speed * 3.6).round()} km/h) '
      'acc=${position.accuracy.toStringAsFixed(0)}m',
    );
  }

  /// Start watching GPS for arrival at [destinationName]. When the
  /// proximity check sees us inside the home zone, [onNearHome] is invoked
  /// with the target destination. The decision to actually show a
  /// notification lives with the caller (typically [BackgroundService]),
  /// which gates on whether a trip is still active — without that gate
  /// the timer would re-post "Oletko perillä?" every 30 s long after the
  /// trip ended.
  Future<void> startMonitoringDestination(
    String destinationName,
    AppSettings settings,
    Future<void> Function(String destination) onNearHome,
  ) async {
    if (_isMonitoring) await stopMonitoring();

    _targetLocation = destinationName;

    final hasPerm = await hasPermissionGranted();
    if (!hasPerm) return;

    _isMonitoring = true;
    _lastHeartbeatAt = null;

    final settingsForStream = tripLocationSettings();
    LogService().info(
      'GPS: trip tracking started — foreground service: '
      '${isForegroundBacked(settingsForStream)}, '
      'permission: ${await _permissionLabel()}',
    );

    _positionStream = openTripPositionStream(settingsForStream).listen(
      (position) {
        _currentPosition = position;
        _logHeartbeat(position);
        if (!_positionController.isClosed) {
          _positionController.add(position);
        }
      },
      onError: (Object e) {
        // A transient location error must not leak as an unhandled
        // async error; monitoring simply pauses until the next fix.
        LogService().warn('GPS: position stream error: $e');
      },
      cancelOnError: false,
    );

    _proximityTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
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
            pos.latitude,
            pos.longitude,
            zone.latitude,
            zone.longitude,
          );
          if (dist <= zone.radiusMeters + 200) {
            // a bit of grace
            nearHome = true;
            break;
          }
        }
      }

      if (nearHome) {
        await onNearHome(_targetLocation!);
      }
    });
  }

  /// Stop trip tracking. Cancelling the subscription also tears down
  /// geolocator's location foreground service (and its notification), so the
  /// service — and its battery cost — exists only while a trip is running.
  Future<void> stopMonitoring() async {
    final wasMonitoring = _isMonitoring;
    _isMonitoring = false;
    _targetLocation = null;
    _lastHeartbeatAt = null;
    _proximityTimer?.cancel();
    _proximityTimer = null;
    await _positionStream?.cancel();
    _positionStream = null;
    if (wasMonitoring) LogService().info('GPS: trip tracking stopped');
  }

  void dispose() {
    stopMonitoring();
    _positionController.close();
  }

  /// Haversine distance in meters between two lat/lon points.
  static double haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371000;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRadians(double degrees) => degrees * pi / 180.0;
}
