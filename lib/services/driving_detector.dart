/// Pure speed-based driving/arrival state machine.
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
