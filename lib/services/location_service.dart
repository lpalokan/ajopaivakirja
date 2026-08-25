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

  /// How far the device must move before the idle (no trip running) position
  /// stream emits another fix. Coarser than the trip filter: this stream only
  /// feeds the home screen's "where am I" chip and the nearby-route list, and
  /// both are answered at the granularity of a named place.
  static const int idleDistanceFilterMeters = 100;

  /// How close a known [LocationZone] has to be before we call it "where I
  /// am". Deliberately larger than a zone's own radius: the driver is usually
  /// on the street outside the geofence, not standing in its centre, and both
  /// the position chip and the nearby-route list would otherwise go blank
  /// exactly where they are most useful.
  static const double nearbyMatchRadiusMeters = 500;

  /// Radius given to a zone the app learns by itself (see [rememberPlace]).
  static const double learnedZoneRadiusMeters = 200;

  /// A learned zone is only worth saving from a fix this accurate. A 500 m
  /// scatter would name the wrong place for every later visit.
  static const double learnAccuracyLimitMeters = 100;

  /// Minimum gap between "GPS: fix" heartbeat log lines. The log is the only
  /// way to tell, from a drive shared through Settings → Virheloki, whether
  /// fixes kept arriving once the screen was locked — but one line per fix
  /// would flood it, so the heartbeat is throttled to one a minute.
  static const Duration gpsHeartbeatInterval = Duration(minutes: 1);

  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  DateTime? _lastHeartbeatAt;
  DateTime? _lastIdleHeartbeatAt;

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
  ///
  /// [timeLimit] is passed to the platform so a fix that never arrives fails
  /// here rather than leaving the caller to race it with its own timeout —
  /// which is what made the home screen give up after 3 s and show a stale
  /// place for the rest of the session.
  Future<Position?> getCurrentPosition({
    Duration timeLimit = const Duration(seconds: 15),
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) async {
    try {
      _currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          timeLimit: timeLimit,
        ),
      );
      return _currentPosition;
    } catch (_) {
      return null;
    }
  }

  /// The platform's cached fix, if any. Costs no GPS time, so it is what the
  /// home screen shows *while* a real fix is being acquired.
  Future<Position?> getLastKnownPosition() async {
    try {
      return await Geolocator.getLastKnownPosition();
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
    final matches = matchZones(
      zones,
      position.latitude,
      position.longitude,
      slackMeters: 0,
    );
    return matches.isEmpty ? null : matches.first.zone;
  }

  /// Every known location the driver can reasonably be said to be at right
  /// now, nearest first. A zone counts when the fix is inside its own radius
  /// *or* within [slackMeters] of its centre, so a wide zone stays a match
  /// from the inside and a small one still matches from the street outside.
  static List<ZoneMatch> matchZones(
    List<LocationZone> zones,
    double latitude,
    double longitude, {
    double slackMeters = nearbyMatchRadiusMeters,
  }) {
    final matches = <ZoneMatch>[];
    for (final zone in zones) {
      final dist = haversineDistance(
        latitude,
        longitude,
        zone.latitude,
        zone.longitude,
      );
      final limit = zone.radiusMeters > slackMeters
          ? zone.radiusMeters
          : slackMeters;
      if (dist <= limit) {
        matches.add(ZoneMatch(zone: zone, distanceMeters: dist));
      }
    }
    matches.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return matches;
  }

  /// The known locations the driver is at right now, nearest first.
  Future<List<ZoneMatch>> findNearbyZones(Position position) async {
    final zones = await DatabaseService.getAllLocationZones();
    return matchZones(zones, position.latitude, position.longitude);
  }

  /// Get the best location name for the current GPS position.
  /// Returns null if no zone matches.
  Future<String?> getLocationName(Position position) async {
    final matches = await findNearbyZones(position);
    return matches.isEmpty ? null : matches.first.zone.name;
  }

  /// Learn [name] as a known location at [position], so the next visit can be
  /// recognised from GPS alone.
  ///
  /// Without this the whole zone vocabulary has to be entered by hand in
  /// Settings, and on a fresh install nothing on the home screen can be named
  /// or matched. Deliberately conservative: only a name the user has never
  /// used for a zone before, and only from a fix accurate enough to be worth
  /// recognising later. Returns the saved zone, or null when nothing was
  /// learned.
  Future<LocationZone?> rememberPlace(String name, Position? position) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || position == null) return null;
    if (position.accuracy > learnAccuracyLimitMeters) return null;
    // A fix we are no longer allowed to have must not become a permanent
    // record of where the user lives and works.
    if (!await hasPermissionGranted()) return null;

    final zones = await DatabaseService.getAllLocationZones();
    final known = trimmed.toLowerCase();
    if (zones.any((z) => z.name.trim().toLowerCase() == known)) return null;

    final zone = await DatabaseService.insertLocationZone(
      LocationZone(
        name: trimmed,
        latitude: position.latitude,
        longitude: position.longitude,
        radiusMeters: learnedZoneRadiusMeters,
        createdAt: DateTime.now().toIso8601String(),
      ),
    );
    LogService().info(
      'GPS: learned location "$trimmed" at '
      '${position.latitude.toStringAsFixed(4)}, '
      '${position.longitude.toStringAsFixed(4)}',
    );
    return zone;
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

  /// Location settings for the "where am I" stream that runs while the home
  /// screen is open and no trip is in progress.
  ///
  /// Deliberately NOT foreground-service backed (unlike
  /// [tripLocationSettings]): this stream exists only to keep the position
  /// chip and the nearby-route list honest while the driver is looking at
  /// them, and it is cancelled the moment the app is backgrounded. A coarse
  /// distance filter and medium accuracy keep it cheap — the answer is a
  /// place name, not a metre reading.
  static LocationSettings idleLocationSettings() => const LocationSettings(
    accuracy: LocationAccuracy.medium,
    distanceFilter: idleDistanceFilterMeters,
  );

  /// Opens the platform position stream used while idling on the home screen.
  /// Overridden in tests so the wiring can be exercised without Geolocator.
  @protected
  @visibleForOverriding
  Stream<Position> openIdlePositionStream(LocationSettings settings) =>
      Geolocator.getPositionStream(locationSettings: settings);

  /// Live positions for the home screen while no trip is running. Errors are
  /// swallowed into a pause rather than surfacing: a missing fix must never
  /// take the home screen down.
  Stream<Position> watchIdlePosition() =>
      openIdlePositionStream(idleLocationSettings())
          .handleError(
            (Object e) => LogService().warn('GPS: idle stream error: $e'),
          )
          .map((position) {
            _currentPosition = position;
            _logIdleHeartbeat(position);
            return position;
          });

  /// One throttled line per minute while the idle watch is delivering fixes.
  /// This is how the battery question gets answered from a real day rather
  /// than an estimate: no idle lines in Virheloki between two rides means the
  /// watch was not running then.
  void _logIdleHeartbeat(Position position) {
    final now = DateTime.now();
    final last = _lastIdleHeartbeatAt;
    if (last != null && now.difference(last) < gpsHeartbeatInterval) return;
    _lastIdleHeartbeatAt = now;
    LogService().info(
      'GPS: idle fix acc=${position.accuracy.toStringAsFixed(0)}m',
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

/// A known location the driver is currently at, with how far away it is.
class ZoneMatch {
  final LocationZone zone;
  final double distanceMeters;

  const ZoneMatch({required this.zone, required this.distanceMeters});

  String get name => zone.name;

  @override
  String toString() => 'ZoneMatch(${zone.name}, ${distanceMeters.round()}m)';
}
