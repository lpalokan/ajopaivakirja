import 'dart:async';

import 'package:flutter_activity_recognition/flutter_activity_recognition.dart'
    as plugin;

import 'log_service.dart';
import 'sensor_registry.dart';

/// Coarse on-device motion state we care about for trip reminders.
///
/// Mirrors the values that `flutter_activity_recognition` v4 actually emits.
/// (v2 also exposed `ON_FOOT` and `TILTING`; v4 dropped them, so we don't
/// model them.)
enum DrivingActivity {
  inVehicle,
  onBicycle,
  walking,
  running,
  still,
  unknown,
}

DrivingActivity _fromPlugin(plugin.ActivityType t) {
  switch (t) {
    case plugin.ActivityType.IN_VEHICLE:
      return DrivingActivity.inVehicle;
    case plugin.ActivityType.ON_BICYCLE:
      return DrivingActivity.onBicycle;
    case plugin.ActivityType.WALKING:
      return DrivingActivity.walking;
    case plugin.ActivityType.RUNNING:
      return DrivingActivity.running;
    case plugin.ActivityType.STILL:
      return DrivingActivity.still;
    case plugin.ActivityType.UNKNOWN:
      return DrivingActivity.unknown;
  }
}

/// Maps a raw plugin reading to our coarse enum, or returns `null` when the
/// reading should be ignored.
///
/// The Activity Recognition framework attaches a [plugin.ActivityConfidence]
/// (HIGH 80–100, MEDIUM 50–80, LOW 0–50) to every detection. A LOW reading is
/// essentially a guess; acting on it lets a spurious `still`/`unknown` flicker
/// — common mid-drive at a traffic light or over a bump — clobber a solid
/// `in_vehicle` state and trip the "Oletko perillä?" reminder while the user
/// is still driving. We drop LOW readings so the last confident activity
/// stands until the framework is reasonably sure it has changed.
///
/// Pure and top-level so it can be unit-tested without the platform plugin.
DrivingActivity? mapActivity(
  plugin.ActivityType type,
  plugin.ActivityConfidence confidence,
) {
  if (confidence == plugin.ActivityConfidence.LOW) return null;
  return _fromPlugin(type);
}

/// Thin wrapper over `flutter_activity_recognition` so the rest of the app
/// depends on a small enum + stream rather than the plugin's types, and tests
/// can substitute a fake that pushes synthetic activity events.
///
/// Best-effort by design: if the plugin throws, the permission is denied, or
/// the device lacks Google Play services, the stream simply never emits and
/// the caller treats the activity as [DrivingActivity.unknown]. The reminder
/// logic in [BackgroundService] then treats `unknown` like "not in a vehicle"
/// — the 5-minute poll asks "Oletko perillä?" instead of suppressing.
class ActivityRecognitionService {
  StreamSubscription<plugin.Activity>? _sub;
  final StreamController<DrivingActivity> _controller =
      StreamController<DrivingActivity>.broadcast();

  Stream<DrivingActivity> get activityStream => _controller.stream;

  Future<bool> _ensurePermission() async {
    try {
      final current =
          await plugin.FlutterActivityRecognition.instance.checkPermission();
      if (current == plugin.ActivityPermission.GRANTED) return true;
      if (current == plugin.ActivityPermission.PERMANENTLY_DENIED) {
        LogService().warn(
          'Activity: permission permanently denied — in_vehicle suppression '
          'is OFF and reminders fall back to the blind timer',
        );
        return false;
      }
      final asked =
          await plugin.FlutterActivityRecognition.instance.requestPermission();
      if (asked != plugin.ActivityPermission.GRANTED) {
        LogService().warn('Activity: permission request answered $asked');
        return false;
      }
      return true;
    } catch (e) {
      LogService().warn('Activity: permission check failed: $e');
      return false;
    }
  }

  Future<void> start() async {
    if (_sub != null) return;
    final granted = await _ensurePermission();
    if (!granted) return;
    try {
      _sub = plugin.FlutterActivityRecognition.instance.activityStream.listen(
        (a) {
          if (_controller.isClosed) return;
          final mapped = mapActivity(a.type, a.confidence);
          if (mapped == null) return; // LOW-confidence noise — keep last reading
          _controller.add(mapped);
        },
        onError: (Object e) {
          // The plugin surfaces failures (e.g. requestActivityUpdates being
          // rejected by Play services) as stream errors. They must be
          // visible in the log: a silent failure here is exactly the
          // "reminder fired after 30 minutes even though I was driving"
          // bug from the outside.
          LogService().warn('Activity: stream error: $e');
        },
      );
      LogService().info('Activity: recognition stream started');
      // Play Services asks for activity updates every second while this is
      // open, and bills them through the same machinery as location — so it
      // belongs in the same ledger as the position streams.
      SensorRegistry().acquired(
        SensorHold.activityRecognition,
        detail: 'requestActivityUpdates 1s',
      );
    } catch (e) {
      LogService().warn('Activity: stream unavailable: $e');
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    SensorRegistry().released(SensorHold.activityRecognition);
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    if (!_controller.isClosed) _controller.close();
  }
}
