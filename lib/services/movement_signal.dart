/// Whether the vehicle is moving right now, judged from the position feed.
///
/// This is what gates the "Oletko perillä?" reminder while a trip is running.
/// Activity Recognition alone is not enough: the Android framework only emits
/// when its reading *changes*, so on a long steady drive it reports
/// `in_vehicle` once and then goes quiet, and a single spurious `still` —
/// routine with a phone in a cradle — used to be enough to ask "have you
/// arrived?" at 90 km/h.
///
/// Deliberately a recency check rather than a state machine. A parked vehicle
/// often produces **no samples at all**, so "how long has it been stopped?"
/// has no answer; "when did we last see driving speed?" does.
library;

import 'dart:math';

class MovementSignal {
  /// At or above this speed (m/s) a sample counts as driving.
  final double highSpeedMps;

  /// How long a fast sample keeps counting as "still driving". Long enough to
  /// ride out a tunnel, a long red light or a coffee stop's worth of GPS
  /// silence; short enough that a real arrival prompts within a poll or two.
  final Duration recency;

  MovementSignal({
    this.highSpeedMps = defaultHighSpeedMps,
    this.recency = const Duration(minutes: 5),
  });

  /// 5 m/s — 18 km/h. Fast enough that walking never counts, slow enough that
  /// crawling traffic still does.
  static const double defaultHighSpeedMps = 5.0;

  DateTime? _lastFastSampleAt;
  DateTime? _lastSampleAt;
  double? _lastLatitude;
  double? _lastLongitude;

  /// When a sample at or above [highSpeedMps] last arrived.
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
    if (speed >= highSpeedMps) _lastFastSampleAt = at;
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
