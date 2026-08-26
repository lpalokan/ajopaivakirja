/// Per-diem (päiväraha) entitlement for one 24-hour travel day.
enum AllowanceType {
  /// Osapäiväraha — the half rate.
  half,

  /// Kokopäiväraha — the full rate.
  full,
}

/// One travel day's entitlement: when its 24-hour period began, and what it
/// earns.
class TravelDay {
  /// Start of this matkavuorokausi. The first one begins at departure; each
  /// subsequent one 24 hours after the previous.
  final DateTime start;

  /// How long this period lasted. A complete travel day is 24 h; only the
  /// last one can be shorter.
  final Duration duration;

  final AllowanceType type;

  const TravelDay({
    required this.start,
    required this.duration,
    required this.type,
  });

  /// The calendar date this travel day begins on, `yyyy-MM-dd`. Used to show
  /// the allowance against a day in the log, so a two-day trip reads as one
  /// päiväraha per day rather than everything landing on the return.
  String get date =>
      '${start.year.toString().padLeft(4, '0')}-'
      '${start.month.toString().padLeft(2, '0')}-'
      '${start.day.toString().padLeft(2, '0')}';

  @override
  String toString() =>
      'TravelDay($date, ${duration.inMinutes}min, ${type.name})';
}

/// Split a työmatka into travel days and decide what each one earns.
///
/// The rule (Verohallinto, "Työmatkakustannusten korvaukset verotuksessa"):
///
/// - A **matkavuorokausi** is 24 hours from the moment of departure. Each
///   complete one earns kokopäiväraha.
/// - Of the final, incomplete travel day: more than **6 hours** earns
///   kokopäiväraha, more than **2 hours** earns osapäiväraha, less earns
///   nothing.
/// - A trip that never completes a travel day is judged on its total: more
///   than **10 hours** earns kokopäiväraha, more than **6 hours** earns
///   osapäiväraha, less earns nothing.
///
/// This is the whole reason the calculation cannot be done per calendar
/// date: a trip that leaves on Monday morning and returns Tuesday afternoon
/// earns two full päivärahat, but neither Monday nor Tuesday on its own
/// looks like more than a few hours of driving.
List<TravelDay> travelDaysFor(DateTime departure, DateTime returnAt) {
  final total = returnAt.difference(departure);
  if (total <= Duration.zero) return const [];

  const day = Duration(hours: 24);
  final completeDays = total.inMinutes ~/ day.inMinutes;
  final remainder = total - day * completeDays;

  // Inside a single travel day: judged on the total, not on a remainder.
  if (completeDays == 0) {
    final type = _typeForSingleDay(total);
    if (type == null) return const [];
    return [TravelDay(start: departure, duration: total, type: type)];
  }

  final days = <TravelDay>[
    for (var i = 0; i < completeDays; i++)
      TravelDay(
        start: departure.add(day * i),
        duration: day,
        type: AllowanceType.full,
      ),
  ];

  final lastType = _typeForRemainder(remainder);
  if (lastType != null) {
    days.add(
      TravelDay(
        start: departure.add(day * completeDays),
        duration: remainder,
        type: lastType,
      ),
    );
  }

  return days;
}

AllowanceType? _typeForSingleDay(Duration total) {
  if (total > const Duration(hours: 10)) return AllowanceType.full;
  if (total > const Duration(hours: 6)) return AllowanceType.half;
  return null;
}

AllowanceType? _typeForRemainder(Duration remainder) {
  if (remainder > const Duration(hours: 6)) return AllowanceType.full;
  if (remainder > const Duration(hours: 2)) return AllowanceType.half;
  return null;
}
