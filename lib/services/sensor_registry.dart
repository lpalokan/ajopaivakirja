import 'dart:async';

import 'log_service.dart';

/// A platform subscription the app can be holding open, i.e. something the
/// operating system bills to the app for as long as it lasts.
///
/// Named rather than boolean because "the GPS was on for 8 h 56 m" is the
/// question that cost two rounds of guesswork: Samsung's battery screen says
/// how long, never who, and the two location requests this app makes have
/// wildly different costs.
enum SensorHold {
  /// The trip position stream: high accuracy, 5 s interval, under a location
  /// foreground service. The expensive one.
  tripLocation('Ajon sijaintiseuranta'),

  /// The home screen's "where am I" watch: medium accuracy, 100 m filter, no
  /// foreground service. Cheap, but only while someone is looking at it — and
  /// it delivers almost nothing from a parked car, so it can be held for
  /// hours without writing a single line to the log.
  idleLocation('Kotinäkymän sijaintiseuranta'),

  /// A one-shot `getCurrentPosition`. Meant to last seconds; listed because a
  /// call that never comes back looks, from the outside, exactly like a
  /// stream that was never closed.
  oneShotLocation('Kertaluontoinen sijaintihaku'),

  /// Activity Recognition updates. Not a location request, but Play Services
  /// bills it through the same machinery, so it belongs in the same list.
  activityRecognition('Liiketunnistus');

  const SensorHold(this.label);

  /// Finnish name, shown in Settings → Vianmääritys.
  final String label;
}

/// What the app is currently making the phone do, and since when.
///
/// One process-wide instance, deliberately not injected: every holder is a
/// singleton service already, and a registry that some code paths could
/// bypass would answer the wrong question. Keeping it free of any dependency
/// on the widget tree also means the background isolate can read it.
///
/// Costs nothing when idle. The periodic "still held" line is the only timer
/// it ever runs, and that is gated on debug logging being switched on.
class SensorRegistry {
  static final SensorRegistry _instance = SensorRegistry._();
  factory SensorRegistry() => _instance;
  SensorRegistry._();

  /// How often the "these are still held" line is written while anything is
  /// held. Frequent enough to show a hold surviving hours, rare enough that
  /// the line itself is not a battery item. Gaps between lines are
  /// informative in their own right: they are the phone dozing.
  static const Duration heartbeatInterval = Duration(minutes: 5);

  final Map<SensorHold, DateTime> _heldSince = {};
  Timer? _heartbeat;

  /// Everything held right now, with the moment each was acquired.
  Map<SensorHold, DateTime> get heldSince => Map.unmodifiable(_heldSince);

  bool get anythingHeld => _heldSince.isNotEmpty;

  bool isHeld(SensorHold hold) => _heldSince.containsKey(hold);

  /// Record that [hold] is now open. [detail] is free text for the log line —
  /// the settings the request was made with, or why it was needed.
  void acquired(SensorHold hold, {String? detail}) {
    if (_heldSince.containsKey(hold)) {
      // Re-acquiring without releasing is itself worth knowing about: it
      // means somebody lost track of a subscription that is still open.
      LogService().warn(
        'POWER: ${hold.name} acquired while already held '
        '(since ${_heldSince[hold]})',
      );
      return;
    }
    _heldSince[hold] = DateTime.now();
    LogService().info(
      'POWER: ${hold.name} acquired${detail == null ? '' : ' ($detail)'} '
      '— now holding: ${_names()}',
    );
    _ensureHeartbeat();
  }

  /// Record that [hold] is closed. Releasing something that was not held is
  /// silent: teardown paths are deliberately idempotent.
  void released(SensorHold hold) {
    final since = _heldSince.remove(hold);
    if (since == null) return;
    LogService().info(
      'POWER: ${hold.name} released after ${formatDuration(_elapsed(since))} '
      '— now holding: ${_names()}',
    );
    if (_heldSince.isEmpty) {
      _heartbeat?.cancel();
      _heartbeat = null;
    }
  }

  /// Record something that is not a hold but explains one: an app lifecycle
  /// change, a refused request, a stand-down. These are what turn the log
  /// from a list of states into a story.
  void note(String message) => LogService().info('POWER: $message');

  /// One line naming everything held and for how long. Shown in Settings and
  /// written by the heartbeat.
  String summary({DateTime? now}) {
    if (_heldSince.isEmpty) return 'Ei mitään käynnissä';
    final at = now ?? DateTime.now();
    final parts = _heldSince.entries.map(
      (e) => '${e.key.label} ${formatDuration(at.difference(e.value))}',
    );
    return parts.join(', ');
  }

  /// Wipe the registry. For tests only — a scenario must not inherit the
  /// holds of the one before it.
  void resetForTesting() {
    _heldSince.clear();
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  Duration _elapsed(DateTime since) => DateTime.now().difference(since);

  String _names() => _heldSince.isEmpty
      ? 'nothing'
      : _heldSince.keys.map((h) => h.name).join(', ');

  void _ensureHeartbeat() {
    if (_heartbeat != null) return;
    // No logging, no timer: the registry still answers the Settings panel
    // from the map above, which costs nothing to keep.
    if (!LogService().isEnabled) return;
    _heartbeat = Timer.periodic(heartbeatInterval, (_) {
      if (_heldSince.isEmpty) return;
      LogService().info('POWER: still holding — ${summary()}');
    });
  }

  /// "8 h 20 min" / "41 min" / "12 s" — the resolution a battery question is
  /// actually asked at.
  static String formatDuration(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds} s';
    if (d.inHours < 1) return '${d.inMinutes} min';
    return '${d.inHours} h ${d.inMinutes % 60} min';
  }
}
