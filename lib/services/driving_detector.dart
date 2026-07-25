/// Pure speed-based driving/arrival state machines.
///
/// This is the brain that [TripDetectionService] used to carry inline,
/// tangled with the Geolocator position stream and a periodic [Timer]. Pulled
/// out, it has no platform dependencies, so the thresholds and the
/// monitoring → driving → arrived transitions can be exercised with plain
/// unit tests instead of a real GPS feed.
///
/// Usage from the adapter: feed every position's speed through [onSample],
/// and call [tick] on the sampling interval; [tick] returns a [DetectionEvent]
/// at the moment a transition fires (or null otherwise).
library;

import 'dart:math';

enum DetectionState { idle, monitoring, driving, arrived }

/// Emitted by [DrivingDetector.tick] when the machine crosses a threshold.
enum DetectionEvent { drivingDetected, arrivedDetected }

/// Tunable thresholds for the detector. Defaults are the values that used to
/// be hard-coded in TripDetectionService, so behaviour is unchanged; having
/// them named in one place makes them adjustable and testable.
class DetectionConfig {
  /// At or above this speed (m/s) the device is "moving fast".
  final double highSpeed;

  /// Below this speed (m/s) the device counts as "stopped".
  final double lowSpeed;

  /// Sustained fast movement for this many seconds → driving detected.
  final int drivingAfterSeconds;

  /// Sustained stop for this many seconds (after driving) → arrival detected.
  final int arrivedAfterSeconds;

  /// Seconds each [onSample] represents and the cadence [tick] is expected to
  /// be called at. Counters advance by this much per sample.
  final int sampleIntervalSeconds;

  const DetectionConfig({
    this.highSpeed = 5.0,
    this.lowSpeed = 1.0,
    this.drivingAfterSeconds = 30,
    this.arrivedAfterSeconds = 60,
    this.sampleIntervalSeconds = 10,
  });
}

class DrivingDetector {
  final DetectionConfig config;

  DrivingDetector({this.config = const DetectionConfig()});

  DetectionState _state = DetectionState.idle;
  DetectionState get state => _state;

  int _highSpeedSeconds = 0;
  int _lowSpeedSeconds = 0;
  bool _wasDriving = false;

  /// Begin watching for the start of a drive (idle → monitoring).
  void startMonitoring() {
    _state = DetectionState.monitoring;
    _highSpeedSeconds = 0;
    _lowSpeedSeconds = 0;
    _wasDriving = false;
  }

  /// Jump straight to the driving state because a trip was started by hand,
  /// so the machine watches for arrival next. Mirrors the old
  /// `resetAfterTripStart`: it does NOT set [_wasDriving], so arrival is only
  /// auto-detected once real driving has been observed.
  void markTripStarted() {
    _state = DetectionState.driving;
    _highSpeedSeconds = 0;
    _lowSpeedSeconds = 0;
  }

  /// Return to idle and clear the counters.
  void reset() {
    _state = DetectionState.idle;
    _highSpeedSeconds = 0;
    _lowSpeedSeconds = 0;
  }

  /// Fold one speed reading into the counters.
  void onSample(double speed) {
    if (speed >= config.highSpeed) {
      _highSpeedSeconds += config.sampleIntervalSeconds;
      _lowSpeedSeconds = 0;
    } else if (speed < config.lowSpeed && _state == DetectionState.driving) {
      _lowSpeedSeconds += config.sampleIntervalSeconds;
    } else {
      // Between low and high speed: reset the stop counter but don't accrue
      // fast-movement time.
      _lowSpeedSeconds = 0;
    }
  }

  /// Evaluate the accumulated counters against the thresholds. Returns the
  /// transition event if one fires this tick, otherwise null.
  DetectionEvent? tick() {
    switch (_state) {
      case DetectionState.monitoring:
        if (_highSpeedSeconds >= config.drivingAfterSeconds) {
          _state = DetectionState.driving;
          _wasDriving = true;
          return DetectionEvent.drivingDetected;
        }
        break;

      case DetectionState.driving:
        if (_lowSpeedSeconds >= config.arrivedAfterSeconds && _wasDriving) {
          _state = DetectionState.arrived;
          _wasDriving = false;
          _highSpeedSeconds = 0;
          _lowSpeedSeconds = 0;
          return DetectionEvent.arrivedDetected;
        }
        break;

      default:
        break;
    }
    return null;
  }
}

/// "Has this device moved at driving speed recently?", for an irregular feed.
///
/// [DrivingDetector] is the richer machine, but it assumes a fixed-cadence
/// feed: every [DetectionConfig.sampleIntervalSeconds] its counters advance by
/// that much. The position stream a trip runs on is *distance*-filtered, so
/// samples arrive several seconds apart while moving and **stop arriving at
/// all** once the vehicle is parked — under which the stop counter would never
/// accrue and the machine would never reach [DetectionState.arrived]. For that
/// shape of input the answerable question is recency: when did we last see a
/// sample at driving speed?
///
/// This is what gates the "Oletko perillä?" reminder. Activity Recognition
/// alone is not enough: the Android framework only emits when its reading
/// *changes*, so on a long steady drive it reports `in_vehicle` once and then
/// goes quiet, and a single spurious `still` — routine with a phone in a
/// cradle — used to be enough to ask "have you arrived?" at 90 km/h.
class MovementSignal {
  final DetectionConfig config;

  /// How long a fast sample keeps counting as "still driving". Long enough to
  /// ride out a tunnel, a long red light or a coffee stop's worth of GPS
  /// silence; short enough that a real arrival prompts within a poll or two.
  final Duration recency;

  MovementSignal({
    this.config = const DetectionConfig(),
    this.recency = const Duration(minutes: 5),
  });

  DateTime? _lastFastSampleAt;
  DateTime? _lastSampleAt;
  double? _lastLatitude;
  double? _lastLongitude;

  /// When a sample at or above [DetectionConfig.highSpeed] last arrived.
  DateTime? get lastFastSampleAt => _lastFastSampleAt;

  /// When any sample last arrived. Null means the position feed has never
  /// produced anything this trip — no evidence either way, as opposed to
  /// evidence of a stop.
  DateTime? get lastSampleAt => _lastSampleAt;

  /// Fold one position fix into the signal.
  ///
  /// [speedMps] is the reported instantaneous speed. The fused location
  /// provider sometimes hands back a valid fix with `speed == 0`, so when
  /// coordinates are supplied the speed implied by the displacement since the
  /// previous fix is computed too, and the larger of the two wins.
  void onSample({
    required double speedMps,
    required DateTime at,
    double? latitude,
    double? longitude,
  }) {
    var speed = speedMps;

    final prevAt = _lastSampleAt;
    if (latitude != null &&
        longitude != null &&
        _lastLatitude != null &&
        _lastLongitude != null &&
        prevAt != null) {
      final seconds = at.difference(prevAt).inMilliseconds / 1000.0;
      if (seconds > 0) {
        final metres = _haversineMetres(
          _lastLatitude!,
          _lastLongitude!,
          latitude,
          longitude,
        );
        final derived = metres / seconds;
        if (derived > speed) speed = derived;
      }
    }

    _lastSampleAt = at;
    _lastLatitude = latitude;
    _lastLongitude = longitude;
    if (speed >= config.highSpeed) _lastFastSampleAt = at;
  }

  /// True while a fast sample is still fresh enough to mean "driving".
  bool isDrivingAt(DateTime now) {
    final last = _lastFastSampleAt;
    return last != null && now.difference(last) < recency;
  }

  /// Forget everything. Called at trip start and stop.
  void reset() {
    _lastFastSampleAt = null;
    _lastSampleAt = null;
    _lastLatitude = null;
    _lastLongitude = null;
  }

  static double _haversineMetres(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) *
            cos(lat2 * pi / 180.0) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}
