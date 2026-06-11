import 'package:shared_preferences/shared_preferences.dart';

/// Persists the small slice of reminder state that must survive isolate
/// boundaries and process death.
///
/// On Android a notification action declared with `showsUserInterface: false`
/// ("Ajan yhä") is ALWAYS delivered to a separate background isolate — even
/// while the app's foreground engine is alive — so the tap can never reach
/// the live [BackgroundService] directly. The only channel the background
/// isolate has back to the in-app reminder loop (the 5-minute poll and the
/// 30-second proximity check) is persisted state: the tap writes a snooze
/// deadline here, and [BackgroundService] re-reads it before showing any
/// "Oletko perillä?" prompt.
///
/// The destination is stored at trip start so the background isolate can
/// re-arm the platform backstop notification with a meaningful text after it
/// has had to cancel the pending one (cancelling the visible copy of id 3
/// also unschedules it).
class ReminderStore {
  static const _snoozedUntilKey = 'still_driving_snoozed_until_ms';
  static const _destinationKey = 'reminder_destination';

  Future<void> setSnoozedUntil(DateTime until) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_snoozedUntilKey, until.millisecondsSinceEpoch);
  }

  Future<DateTime?> snoozedUntil() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_snoozedUntilKey);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setDestination(String destination) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_destinationKey, destination);
  }

  Future<String?> destination() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_destinationKey);
  }

  /// Wipes all reminder state. Called at trip start and stop so a stale
  /// snooze from a previous trip can never silence the next one.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_snoozedUntilKey);
    await prefs.remove(_destinationKey);
  }
}
