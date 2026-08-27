import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/trip_leg.dart';
import 'activity_recognition_service.dart';
import 'driving_detector.dart';
import 'location_service.dart';
import 'log_service.dart';
import 'notification_service.dart';
import 'reminder_store.dart';

class BackgroundService {
  /// How often the in-process poll re-checks whether the driver is still in
  /// a vehicle. Every increment the current motion is consulted: while the
  /// activity is `in_vehicle` the prompt is suppressed entirely, and only
  /// once the framework reports the driver has left the vehicle is the
  /// "Oletko perillä?" reminder shown. Short (5 min) because the
  /// activity check — not a blind timer — gates whether anything is shown,
  /// so it no longer fires mid-drive the way the old 30/45-minute blind
  /// backstop did.
  static const Duration defaultReminderDuration = Duration(minutes: 5);

  /// How long to wait before the FIRST reminder check of a trip. Longer than
  /// the steady-state poll on purpose: the Android Activity Recognition API
  /// has real latency — at the start of a drive it reports `still`/`unknown`
  /// for a while and only settles into `in_vehicle` after a minute or three
  /// of sustained motion. Polling at 5 minutes meant the very first tick
  /// could fire mid-drive (before the framework had confirmed `in_vehicle`)
  /// and wrongly ask "Oletko perillä?". Deferring the first check to 30
  /// minutes gives the framework ample time to settle; after that first tick
  /// the poll drops back to [defaultReminderDuration].
  static const Duration defaultFirstReminderDuration = Duration(minutes: 30);

  /// Far-out platform-scheduled fallback that only matters if the app
  /// process is killed before any in-process poll can run (an in-process
  /// [Timer] dies with the process). While the process is alive each poll
  /// pushes this fallback forward, so it never actually fires; it is the
  /// blind safety net for "process died mid-trip", deliberately kept long
  /// so that net is not aggressive.
  static const Duration defaultPlatformBackstopDuration = Duration(minutes: 45);

  /// How recently the framework must have reported `in_vehicle` for the poll
  /// to keep suppressing the prompt even though the LATEST reading says
  /// otherwise. Activity Recognition routinely emits a confident `still` at
  /// a red light (and maps a jostled phone to `walking`), so acting on a
  /// single instantaneous reading fired "Oletko perillä?" mid-drive. Only
  /// after the vehicle signal has been absent for this long is a non-vehicle
  /// reading treated as a real stop.
  ///
  /// Note this window can only ever be a partial defence, which is why the
  /// GPS signal below exists: [_lastInVehicleAt] is refreshed when an
  /// activity event is *emitted*, and the Android framework only emits on a
  /// *change* of reading. A steady drive produces one `in_vehicle` event at
  /// the start and then silence, so by minute 30 the timestamp is half an
  /// hour stale and this window has already lapsed.
  static const Duration defaultInVehicleRecencyWindow = Duration(minutes: 10);

  /// How long a GPS fix at driving speed keeps the prompt suppressed.
  ///
  /// This is the signal that actually holds up on a long drive. Unlike
  /// Activity Recognition, the position stream keeps producing while the
  /// vehicle moves, so a fresh fast fix is direct evidence that the trip is
  /// still in progress — whatever the motion classifier currently claims, and
  /// even when it is unavailable altogether. Five minutes is long enough to
  /// ride out a tunnel or a level crossing without re-asking, short enough
  /// that a genuine arrival still prompts within a poll or two.
  static const Duration defaultMovementRecencyWindow = Duration(minutes: 5);

  final NotificationService _notificationService;
  final LocationService _locationService;
  final ActivityRecognitionService _activityService;
  final ReminderStore _reminderStore;
  final Duration _reminderDuration;
  Duration _firstReminderDuration;
  final Duration _platformBackstopDuration;
  Duration _inVehicleRecencyWindow;
  Duration _movementRecencyWindow;

  Timer? _reminderTimer;

  /// When the pending reminder tick was supposed to run, and how many have
  /// run this trip. A tick that fires far later than scheduled means the
  /// process was frozen or dozed rather than "the signals went quiet" — the
  /// two look identical in a bug report otherwise (issue #77).
  DateTime? _nextTickDueAt;
  int _tickCount = 0;

  /// True until the first reminder of the current trip has been scheduled, so
  /// that the opening tick waits [_firstReminderDuration] (long) while every
  /// later reschedule uses [_reminderDuration] (the short steady-state poll).
  bool _firstReminderPending = false;
  StreamSubscription<DrivingActivity>? _activitySub;
  DrivingActivity _lastActivity = DrivingActivity.unknown;

  /// When the framework last reported `in_vehicle`, for the recency check
  /// above. Null until the first in-vehicle reading of the trip.
  DateTime? _lastInVehicleAt;

  /// GPS-speed evidence of driving, fed from the position stream
  /// [LocationService] already publishes throughout a trip. Rebuilt per trip
  /// so [_movementRecencyWindow] changes made by a test seam take effect.
  MovementSignal _movement = MovementSignal();
  StreamSubscription<Position>? _positionSub;

  /// The snooze deadline this isolate has already reacted to. "Ajan yhä" is
  /// handled entirely in the background isolate (see
  /// [handleStillDrivingBackgroundAction]); the main isolate discovers the
  /// tap by noticing a snooze value in [ReminderStore] it hasn't seen
  /// before, at which point it clears the once-per-stop latch so the prompt
  /// is re-asked after the snooze expires.
  DateTime? _lastSeenSnooze;

  /// True once the activity-recognition stream has delivered at least one
  /// reading this trip. Lets the poll tell apart "framework is unavailable"
  /// (no reading ever arrived → fall back to firing the reminder) from
  /// "framework is active but currently unsure" (a confident `unknown` →
  /// suppress, because firing on uncertainty is what surfaced "Oletko
  /// perillä?" mid-drive).
  bool _activityReceived = false;

  /// True once the "Oletko perillä?" reminder has been shown for the
  /// current out-of-vehicle episode, so the 5-minute poll asks once per stop
  /// instead of re-posting the same prompt on every increment. Reset when
  /// the activity returns to `in_vehicle` (a fresh stop can prompt again) or
  /// when the driver taps "Ajan yhä" (snooze, then re-ask if still stopped).
  bool _reminderShown = false;

  TripLeg? _activeLeg;

  void Function()? onArrived;
  void Function()? onStillDriving;

  BackgroundService({
    required NotificationService notificationService,
    required LocationService locationService,
    required ActivityRecognitionService activityService,
    ReminderStore? reminderStore,
    Duration reminderDuration = defaultReminderDuration,
    Duration firstReminderDuration = defaultFirstReminderDuration,
    Duration platformBackstopDuration = defaultPlatformBackstopDuration,
    Duration inVehicleRecencyWindow = defaultInVehicleRecencyWindow,
    Duration movementRecencyWindow = defaultMovementRecencyWindow,
  }) : _notificationService = notificationService,
       _locationService = locationService,
       _activityService = activityService,
       _reminderStore = reminderStore ?? ReminderStore(),
       _reminderDuration = reminderDuration,
       _firstReminderDuration = firstReminderDuration,
       _platformBackstopDuration = platformBackstopDuration,
       _inVehicleRecencyWindow = inVehicleRecencyWindow,
       _movementRecencyWindow = movementRecencyWindow;

  Future<void> initialize() async {
    await _notificationService.initialize();
    _notificationService.onArrived = () => onArrived?.call();
    _notificationService.onStillDriving = () => onStillDriving?.call();
  }

  /// Test seam: lengthen the first-reminder deferral for a single scenario
  /// without rebuilding the service. Lets the integration harness assert "the
  /// first reminder is held back" by pushing the deferral far beyond the
  /// pump window, instead of relying on a tight wall-clock margin between a
  /// short pump and the timer (which is flaky under the real-time test
  /// binding). Call before the trip starts.
  @visibleForTesting
  void debugSetFirstReminderDuration(Duration duration) {
    _firstReminderDuration = duration;
  }

  /// Test seam: shrink/stretch the in-vehicle recency window for a single
  /// scenario, same rationale as [debugSetFirstReminderDuration].
  @visibleForTesting
  void debugSetInVehicleRecencyWindow(Duration duration) {
    _inVehicleRecencyWindow = duration;
  }

  /// Test seam: shrink/stretch how long a GPS fix at driving speed keeps the
  /// prompt suppressed. Same rationale as the two seams above.
  @visibleForTesting
  void debugSetMovementRecencyWindow(Duration duration) {
    _movementRecencyWindow = duration;
  }

  Future<void> onDrivingStarted(TripLeg leg) async {
    _activeLeg = leg;
    _tickCount = 0;
    _reminderShown = false;
    _firstReminderPending = true;
    _activityReceived = false;
    _lastInVehicleAt = null;
    _lastSeenSnooze = null;

    final destination = leg.endLocation ?? leg.routeDescription ?? 'määränpää';

    // Reset cross-isolate reminder state: wipe any stale snooze from a
    // previous trip and store the destination so the background isolate can
    // re-arm the platform backstop after an "Ajan yhä" tap.
    try {
      await _reminderStore.clear();
      await _reminderStore.setDestination(destination);
    } catch (e) {
      LogService().warn('Reminder: store unavailable at trip start: $e');
    }

    await _notificationService.showDrivingNotification(leg);

    // Watch the position stream for evidence that the vehicle is still
    // moving. Subscribed unconditionally, and BEFORE monitoring starts, so a
    // stream that only begins producing later (permission granted mid-trip,
    // first fix delayed) is still picked up. When no fix ever arrives the
    // signal simply stays empty and the activity checks below decide alone.
    _movement = MovementSignal(recency: _movementRecencyWindow);
    _positionSub?.cancel();
    _positionSub = _locationService.positionStream.listen((p) {
      _movement.onSample(
        speedMps: p.speed,
        at: DateTime.now(),
        latitude: p.latitude,
        longitude: p.longitude,
      );
    });

    final hasLocation = await _locationService.hasPermissionGranted();
    if (hasLocation) {
      // Starts the trip position stream under a location foreground service
      // (see [LocationService.tripLocationSettings]) so fixes keep arriving
      // once the driver locks the screen — without it the movement signal
      // above is fed for a couple of minutes and then goes silent for the
      // rest of the drive.
      await _locationService.startMonitoringDestination(
        destination,
        _onProximityArrived,
      );
    } else {
      // Worth a line: with no position stream the reminder gate is down to
      // Activity Recognition alone, which goes quiet on a steady drive.
      LogService().warn(
        'Reminder: trip start without location permission — no GPS evidence '
        'of driving will be available this trip',
      );
    }

    // Best-effort: if activity recognition isn't available or permission is
    // denied, _lastActivity stays at .unknown, which the poll treats like
    // "not in a vehicle" — so the reminder still surfaces (just without the
    // in_vehicle suppression that would otherwise keep it silent mid-drive).
    _activitySub?.cancel();
    _activitySub = _activityService.activityStream.listen((a) {
      if (a != _lastActivity) {
        LogService().info('Reminder: activity changed to ${a.name}');
      }
      _lastActivity = a;
      _activityReceived = true;
      if (a == DrivingActivity.inVehicle) {
        _lastInVehicleAt = DateTime.now();
      }
    });
    try {
      await _activityService.start();
    } catch (e) {
      // Activity is best-effort, but its absence must be diagnosable: it is
      // the difference between "the app ignored the framework" and "the
      // framework never reported in_vehicle".
      LogService().warn('Reminder: activity recognition failed to start: $e');
    }

    _scheduleTimeBasedReminder(leg);
  }

  void _scheduleTimeBasedReminder(TripLeg leg) {
    _reminderTimer?.cancel();

    final destination = leg.endLocation ?? leg.routeDescription ?? 'määränpää';

    // Platform-level fallback (re)scheduled far enough out that, while the
    // process is alive, the in-process poll below (the long first-tick
    // deferral, then the short steady-state poll) always fires first and
    // pushes this forward again — so it never fires its own copy and there
    // is no duplicate notification. It only fires if the process is killed
    // and no poll runs for the whole backstop window.
    final platformTrigger = DateTime.now().add(_platformBackstopDuration);
    _notificationService.scheduleTimeBasedReminder(
      destination,
      platformTrigger,
    );

    // First tick of a trip waits the long deferral; every subsequent
    // reschedule falls back to the short steady-state poll.
    final nextTick = _firstReminderPending
        ? _firstReminderDuration
        : _reminderDuration;
    _firstReminderPending = false;
    _nextTickDueAt = DateTime.now().add(nextTick);
    _reminderTimer = Timer(nextTick, () => _onReminderTick(leg));
  }

  /// Callback the [LocationService]'s proximity Timer invokes when the
  /// user is inside the home zone. Gated on `_activeLeg != null` so a
  /// proximity tick that fires AFTER the trip ended (race between
  /// `stopMonitoring` and the 30-second tick, or a leaked Timer from a
  /// previous session) does not re-post "Oletko perillä?" indefinitely.
  ///
  /// Also gated on the current activity, the "Ajan yhä" snooze and the
  /// once-per-stop latch: the proximity Timer fires every 30 seconds for as
  /// long as the driver is inside the home zone, and ungated it re-posted
  /// the prompt on every tick — which is why "Ajan yhä" appeared to do
  /// nothing when arriving home (the tap dismissed the notification and the
  /// next 30-second tick put an identical one straight back).
  Future<void> _onProximityArrived(String destination) async {
    if (_activeLeg == null) return;
    // Driving through/into the zone — not an arrival yet. Once the driver
    // parks, the movement signal goes stale and the activity flips to
    // still/walking, and the next 30-second tick prompts. This path used to
    // check only the instantaneous activity, so one spurious `still` while
    // passing through your own neighbourhood was enough to prompt.
    if (_stillDrivingReason() != null) return;
    if (!await _shouldPrompt()) return;
    _reminderShown = true;
    LogService().info('Reminder: proximity prompt for $destination');
    await _notificationService.showArrivalReminder(destination);
  }

  /// Why the driver should be considered still on the road, or null if no
  /// signal says so.
  ///
  /// One place, consulted by both the poll and the proximity check, so the
  /// two can't drift apart — they did, and the weaker proximity gate was its
  /// own source of mid-drive prompts. Returns a human-readable reason so the
  /// log says *which* signal held the prompt back; on a real drive that log
  /// is the only way to tell "the app ignored the framework" from "the
  /// framework never said anything".
  String? _stillDrivingReason() {
    final now = DateTime.now();

    // Strongest signal first: the vehicle is measurably moving. Holds up on
    // long drives, where Activity Recognition has usually gone quiet.
    if (_movement.isDrivingAt(now)) {
      final since = now.difference(_movement.lastFastSampleAt!).inSeconds;
      return 'GPS driving speed ${since}s ago';
    }

    if (_lastActivity == DrivingActivity.inVehicle) return 'in_vehicle';

    final lastInVehicle = _lastInVehicleAt;
    if (lastInVehicle != null &&
        now.difference(lastInVehicle) < _inVehicleRecencyWindow) {
      // The latest reading says not-in-vehicle, but the vehicle signal was
      // seen only moments ago — a confident `still` at a red light or a
      // jostled phone reported as `walking`, not a real stop.
      return '${_lastActivity.name}, but in_vehicle '
          '${now.difference(lastInVehicle).inSeconds}s ago';
    }

    return null;
  }

  /// "tick #3 (0s late)" — the prefix every tick log line carries.
  String _tickLabel() {
    final due = _nextTickDueAt;
    final late = due == null ? 0 : DateTime.now().difference(due).inSeconds;
    return 'tick #$_tickCount (${late}s late)';
  }

  Future<void> _onReminderTick(TripLeg leg) async {
    if (_activeLeg == null) return;
    _tickCount++;

    final stillDriving = _stillDrivingReason();
    if (stillDriving != null) {
      // Suppress the prompt entirely and keep polling. Reset the "shown"
      // latch so that whenever the driver next leaves the vehicle the
      // reminder is asked again for that fresh stop.
      _reminderShown = false;
      LogService().info('Reminder: ${_tickLabel()} suppressed ($stillDriving)');
      _scheduleTimeBasedReminder(leg);
      return;
    }

    if (_activityReceived && _lastActivity == DrivingActivity.unknown) {
      // The framework is reporting but isn't sure (a confident `unknown`,
      // e.g. it lost the vehicle signal in a tunnel or hasn't re-settled
      // after motion). Don't treat uncertainty as arrival — suppress and keep
      // polling, leaving the "shown" latch as-is. The platform backstop (id
      // 3) remains the safety net if the trip really has ended.
      LogService().info(
        'Reminder: ${_tickLabel()} suppressed (confident unknown)',
      );
      _scheduleTimeBasedReminder(leg);
      return;
    }

    if (!_activityReceived) {
      // No activity reading has ever arrived this trip: the framework is
      // unavailable, the permission is denied, or delivery is being
      // throttled. What happens next depends on whether GPS has anything to
      // say — this used to be an unconditional blind prompt, i.e. exactly the
      // "asked me 30 minutes into a drive" bug when both signals were mute.
      if (_movement.lastSampleAt == null) {
        LogService().warn(
          'Reminder: no activity readings and no GPS fixes this trip — both '
          'signals unavailable; falling back to time-based prompt',
        );
      } else {
        LogService().warn(
          'Reminder: no activity readings this trip, but GPS fixes show no '
          'driving speed — treating as a real stop',
        );
      }
    }

    // Confirmed not-in-vehicle (walking/still/etc.) or activity recognition
    // unavailable (no reading ever arrived). Ask once per stop episode
    // — the latch keeps the 5-minute poll from re-posting the same prompt on
    // every increment while the driver stays stopped. The poll keeps running
    // so a later return-to-vehicle (which resets the latch) and a subsequent
    // stop can prompt again.
    if (await _shouldPrompt()) {
      _reminderShown = true;
      LogService().info(
        'Reminder: showing "Oletko perillä?" (activity: ${_lastActivity.name})',
      );
      await _notificationService.showArrivalReminder(
        leg.endLocation ?? leg.routeDescription ?? 'määränpää',
      );
    }
    _scheduleTimeBasedReminder(leg);
  }

  /// Merges the once-per-stop latch with the persisted "Ajan yhä" snooze.
  ///
  /// The snooze is written by the background isolate (the only place the
  /// still-driving tap is ever delivered on Android), so it has to be
  /// re-read from [ReminderStore] before every prompt. A snooze deadline
  /// this isolate hasn't seen before means the driver tapped "Ajan yhä"
  /// since the last check: clear the latch so the prompt is asked again
  /// once the snooze expires (the tap means "not yet", not "never").
  Future<bool> _shouldPrompt() async {
    DateTime? snoozedUntil;
    try {
      snoozedUntil = await _reminderStore.snoozedUntil();
    } catch (e) {
      LogService().warn('Reminder: snooze read failed: $e');
    }
    if (snoozedUntil != null && snoozedUntil != _lastSeenSnooze) {
      _lastSeenSnooze = snoozedUntil;
      _reminderShown = false;
    }
    if (snoozedUntil != null && DateTime.now().isBefore(snoozedUntil)) {
      return false;
    }
    return !_reminderShown;
  }

  Future<void> onDrivingStopped() async {
    _activeLeg = null;
    _nextTickDueAt = null;
    _reminderShown = false;
    _firstReminderPending = false;
    _reminderTimer?.cancel();
    _reminderTimer = null;
    await _activitySub?.cancel();
    _activitySub = null;
    await _positionSub?.cancel();
    _positionSub = null;
    _movement.reset();
    _lastActivity = DrivingActivity.unknown;
    _activityReceived = false;
    _lastInVehicleAt = null;
    _lastSeenSnooze = null;
    try {
      await _activityService.stop();
    } catch (_) {}
    try {
      await _reminderStore.clear();
    } catch (_) {}

    await _notificationService.cancelDrivingNotification();
    await _notificationService.cancelReminders();
    await _locationService.stopMonitoring();
  }

  /// Driver tapped "Ajan yhä" and the response reached the FOREGROUND
  /// handler. On Android this never happens — `showsUserInterface: false`
  /// actions always land in the background isolate, which does the whole
  /// job itself (see [handleStillDrivingBackgroundAction]) — but the wiring
  /// is kept for iOS and as a defensive path: it performs the same
  /// dismissal + persisted snooze so behaviour is identical wherever the
  /// tap is delivered.
  Future<void> onStillDrivingPressed() async {
    if (_activeLeg == null) return;
    await _notificationService.cancelReminders();
    try {
      await _reminderStore.setSnoozedUntil(
        DateTime.now().add(stillDrivingSnoozeDuration),
      );
    } catch (_) {}
    _reminderShown = false;
    _scheduleTimeBasedReminder(_activeLeg!);
  }

  void dispose() {
    _reminderTimer?.cancel();
    _activitySub?.cancel();
    _positionSub?.cancel();
    _activityService.dispose();
    _locationService.dispose();
  }
}
