import '../models/daily_allowance.dart';
import '../models/trip_leg.dart';

/// What each date was paid in päivärahaa, and where that payment belongs in a
/// leg-shaped report.
///
/// Päiväraha is earned per *travel day* — a 24-hour period counted from the
/// moment of departure — while every report the app produces is a list of
/// *legs*. Those two do not line up. The middle day of a three-day trip is a
/// travel day with no driving at all: it earns a full kokopäiväraha and has
/// no leg to hang it on. Before this class the exports simply lost it, and a
/// tax report that under-reports is a tax report that is wrong.
///
/// So the allowance table is the single source of truth here, and this is the
/// one place that decides how its rows are laid over a date's legs:
///
/// - a date's whole päiväraha goes on that date's **last** leg, matching how
///   the reports have always been read (one figure per day, at the end of the
///   day) and keeping the column's sum equal to the day's total;
/// - a travel day with no legs is reported in its own right — see
///   [orphanDates] — rather than silently dropped.
///
/// `TripLeg.dailyAllowance` still carries the same figure as a denormalised
/// copy, written by the calculator when a trip is finalized. Nothing here
/// reads it: one source of truth, and this is it.
class AllowanceLedger {
  final Map<String, List<DailyAllowance>> _byDate;

  AllowanceLedger(Iterable<DailyAllowance> allowances)
    : _byDate = _group(allowances);

  /// A ledger that pays nothing — for callers with no allowance data to hand.
  static final AllowanceLedger empty = AllowanceLedger(const []);

  static Map<String, List<DailyAllowance>> _group(
    Iterable<DailyAllowance> allowances,
  ) {
    final byDate = <String, List<DailyAllowance>>{};
    for (final allowance in allowances) {
      byDate.putIfAbsent(allowance.date, () => []).add(allowance);
    }
    return byDate;
  }

  /// Every date this ledger pays something for, oldest first.
  List<String> get dates => _byDate.keys.toList()..sort();

  /// The allowances earned on [date] (normally one; two only if a travel day
  /// boundary and a calendar boundary happen to fall on the same date).
  List<DailyAllowance> forDate(String date) => _byDate[date] ?? const [];

  /// What [date] was paid, in euros.
  double totalFor(String date) =>
      forDate(date).fold<double>(0, (sum, a) => sum + a.amount);

  /// Everything this ledger pays, in euros.
  double get total =>
      _byDate.keys.fold<double>(0, (sum, date) => sum + totalFor(date));

  /// The päiväraha to print against [leg], given the [legs] recorded for its
  /// date: the date's whole total on the last leg, nothing on the others, so
  /// a day's figure is never counted twice.
  double forLeg(TripLeg leg, List<TripLeg> legs) {
    if (legs.isEmpty) return 0;
    return identical(legs.last, leg) || _keyOf(legs.last) == _keyOf(leg)
        ? totalFor(leg.date)
        : 0;
  }

  /// Travel days that earned a päiväraha on a date with no legs — the days
  /// that used to vanish from every report. Oldest first.
  List<String> orphanDates(Iterable<String> legDates) {
    final withLegs = legDates.toSet();
    return [
      for (final date in dates)
        if (!withLegs.contains(date) && totalFor(date) > 0) date,
    ];
  }

  /// A human-readable Finnish description of what [date] earned, or null when
  /// it earned nothing. Used wherever a report labels the figure.
  String? describe(String date) {
    final allowances = forDate(date);
    if (allowances.isEmpty) return null;
    if (allowances.every((a) => a.isFull)) {
      return allowances.length == 1
          ? 'Kokopäiväraha'
          : '${allowances.length} × kokopäiväraha';
    }
    if (allowances.every((a) => a.isHalf)) {
      return allowances.length == 1
          ? 'Osapäiväraha'
          : '${allowances.length} × osapäiväraha';
    }
    return '${allowances.where((a) => a.isFull).length} × kokopäiväraha, '
        '${allowances.where((a) => a.isHalf).length} × osapäiväraha';
  }

  /// The `Päivärahatyyppi` value for [date]: the shared type when the date's
  /// allowances agree, and null when they do not (or there are none).
  int? typeFor(String date) {
    final allowances = forDate(date);
    if (allowances.isEmpty) return null;
    final first = allowances.first.type;
    return allowances.every((a) => a.type == first) ? first : null;
  }

  static String _keyOf(TripLeg leg) =>
      '${leg.id ?? -1}|${leg.date}|${leg.legOrder}';
}
