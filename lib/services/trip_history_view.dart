import '../models/trip_leg.dart';

/// Pure shaping rules for the trip-history screen.
///
/// These derivations — "is anything unsynced?", "which is the most recent
/// fully-completed-and-synced month?", and the Finnish month name — used to
/// live inline inside `_TripHistoryScreenState._load`, computable only by
/// pumping the whole screen. Pulled out here they take legs as plain data and
/// can be unit-tested directly.
class TripHistoryView {
  TripHistoryView._();

  static const Map<int, String> _monthNamesFi = {
    1: 'Tammikuu',
    2: 'Helmikuu',
    3: 'Maaliskuu',
    4: 'Huhtikuu',
    5: 'Toukokuu',
    6: 'Kesäkuu',
    7: 'Heinäkuu',
    8: 'Elokuu',
    9: 'Syyskuu',
    10: 'Lokakuu',
    11: 'Marraskuu',
    12: 'Joulukuu',
  };

  /// Finnish name of a 1–12 month number, or '' if out of range.
  static String monthNameFi(int month) => _monthNamesFi[month] ?? '';

  /// Whether any leg on any day is not yet synced to Sheets.
  static bool hasUnsynced(Map<String, List<TripLeg>> legsByDate) {
    for (final legs in legsByDate.values) {
      if (legs.any((l) => !l.synced)) return true;
    }
    return false;
  }

  /// The Finnish name of the most recent month whose every leg is both
  /// completed and synced, or null if there is none (or any draft exists).
  ///
  /// [dates] are `yyyy-MM-dd` strings in the database's reverse-chronological
  /// order, so the first matching date wins. A month is considered "complete"
  /// on the strength of a single fully-done day in it — matching the prior
  /// screen behaviour, which broke on the first qualifying date.
  static String? completeMonthName({
    required List<String> dates,
    required Map<String, List<TripLeg>> legsByDate,
    required int draftCount,
  }) {
    if (draftCount != 0) return null;
    for (final date in dates) {
      final legs = legsByDate[date];
      if (legs == null || legs.isEmpty) continue;
      final allComplete = legs.every((l) => l.isCompleted && l.synced);
      if (allComplete) {
        final month = int.parse(date.substring(5, 7));
        return monthNameFi(month);
      }
    }
    return null;
  }
}
