import 'dart:async';

import 'package:flutter_activity_recognition/flutter_activity_recognition.dart'
    as plugin;

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

/// Thin wrapper over `flutter_activity_recognition` so the rest of the app
/// depends on a small enum + stream rather than the plugin's types, and tests
/// can substitute a fake that pushes synthetic activity events.
///
/// Best-effort by design: if the plugin throws, the permission is denied, or
/// the device lacks Google Play services, the stream simply never emits and
/// the caller treats the activity as [DrivingActivity.unknown]. The reminder
/// logic in [BackgroundService] then falls back to the blind 45-minute
/// backstop instead of suppressing.
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
      if (current == plugin.ActivityPermission.PERMANENTLY_DENIED) return false;
      final asked =
          await plugin.FlutterActivityRecognition.instance.requestPermission();
      return asked == plugin.ActivityPermission.GRANTED;
    } catch (_) {
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
          _controller.add(_fromPlugin(a.type));
        },
        onError: (_) {},
      );
    } catch (_) {
      // Plugin unavailable — leave the stream silent.
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    if (!_controller.isClosed) _controller.close();
  }
}
