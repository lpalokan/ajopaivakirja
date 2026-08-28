import 'package:collection/collection.dart';

import '../models/daily_allowance.dart';
import '../models/trip_leg.dart';
import '../models/app_settings.dart';
import 'database_service.dart';
import 'log_service.dart';
import 'travel_day.dart';

class TripCalculator {
  final AppSettings _settings;
  final Map<int, double>? _kmRates;

  TripCalculator(this._settings, {Map<int, double>? kmRates})
    : _kmRates = kmRates;

  double get allowance6h => _settings.allowance6h;
  double get allowance10h => _settings.allowance10h;
  String get homeLocation => _settings.homeLocation;

  /// Get the km rate applicable for a given year.
  /// Looks up from km_rates table first, falls back to settings default.
  double getKmRateForYear(int year) {
    return _kmRates?[year] ?? _settings.kmRate;
  }

  /// Calculate values for a single leg.
  TripLeg calculateLeg(TripLeg leg) {
    final kmDriven = (leg.endOdometer ?? leg.startOdometer) - leg.startOdometer;
    final year = _yearFromDate(leg.date);
    final rate = getKmRateForYear(year);
    final kmAllowance = kmDriven * rate;
    final isReturnHome = leg.isReturnHomeTo(_settings.homeLocation);

    return leg.copyWith(
      kmDriven: kmDriven.toDouble(),
      kmAllowance: double.parse(kmAllowance.toStringAsFixed(2)),
      legDurationHours: 0,
      isReturnHome: isReturnHome,
      dailyAllowance: 0,
    );
  }

  int _yearFromDate(String date) {
    // date is in yyyy-MM-dd format
    try {
      return int.parse(date.substring(0, 4));
    } catch (_) {
      return DateTime.now().year;
    }
  }

  /// Calculate daily allowance for a list of legs on the same date.
  /// Returns the daily allowance amount and total hours away.
  ({double allowance, double totalHours}) calculateDailyAllowance(
    List<TripLeg> legs,
  ) {
    if (legs.isEmpty) return (allowance: 0, totalHours: 0);

    final firstStart = legs.first.startTime;
    final lastEnd = legs.last.endTime ?? legs.last.startTime;

    final totalHours = lastEnd.difference(firstStart).inMinutes / 60.0;

    double allowance = 0;
    if (totalHours > 10) {
      allowance = allowance10h;
    } else if (totalHours > 6) {
      allowance = allowance6h;
    }

    return (
      allowance: allowance,
      totalHours: double.parse(totalHours.toStringAsFixed(2)),
    );
  }

  /// Calculate working time (Työaika) for the day.
  /// Työaika = time between first leg end and last leg start (time at work site).
  /// Total is stored on the last leg, others get 0.
  List<TripLeg> calculateWorkingTimes(List<TripLeg> legs) {
    if (legs.isEmpty) return legs;

    final updated = legs.map((l) => l.copyWith(workingTimeHours: 0)).toList();

    final firstEnd = legs.first.endTime;
    final lastStart = legs.last.startTime;

    // A single leg has no span between first arrival and last departure;
    // and a negative span (clock skew / unordered legs) is not real work.
    double totalWorkingTime = 0;
    if (legs.length >= 2 && firstEnd != null) {
      final hours = lastStart.difference(firstEnd).inMinutes / 60.0;
      totalWorkingTime = hours < 0 ? 0 : hours;
    }

    // Put total working time on the last leg
    updated[updated.length - 1] = updated.last.copyWith(
      workingTimeHours: double.parse(totalWorkingTime.toStringAsFixed(2)),
    );

    return updated;
  }

  /// Finalize a day's legs (pure): calculate all per-leg values, apply the
  /// daily allowance to the last leg (returning home), and update working
  /// times. Returns the updated legs without persisting them — callers own
  /// the writes (see [finalizeAndPersistDay]). This is the single source of
  /// the finalization rules and is exercised directly by unit tests.
  List<TripLeg> finalizeDayLegs(List<TripLeg> legs) {
    if (legs.isEmpty) return legs;

    // Calculate per-leg values
    var updated = legs.map((l) => calculateLeg(l)).toList();

    // Calculate and apply working times
    updated = calculateWorkingTimes(updated);

    // Determine daily allowance: honor manual override if set
    final last = updated.last;
    final double allowance;
    final String mode;
    if (last.dailyAllowanceType != null) {
      allowance = switch (last.dailyAllowanceType) {
        1 => allowance6h,
        2 => allowance10h,
        _ => 0,
      };
      mode = 'manual(type: ${last.dailyAllowanceType})';
    } else {
      final daily = calculateDailyAllowance(updated);
      allowance = daily.allowance;
      mode = 'auto(hours: ${daily.totalHours})';
    }
    LogService().info(
      'Calc: finalizeDay ${updated.length} legs, allowance=$allowance€ ($mode)',
    );

    // Apply daily allowance to the last leg
    updated[updated.length - 1] = last.copyWith(dailyAllowance: allowance);

    // Calculate total day hours and place on last leg
    if (last.endTime != null) {
      final totalHours =
          last.endTime!.difference(updated.first.startTime).inMinutes / 60.0;
      updated[updated.length - 1] = updated.last.copyWith(
        legDurationHours: double.parse(totalHours.toStringAsFixed(2)),
      );
    }

    return updated;
  }

  /// Finalize a day's legs and persist them. Thin IO wrapper over the pure
  /// [finalizeDayLegs]; the computation lives there. The name makes the
  /// database write explicit at the call site.
  Future<List<TripLeg>> finalizeAndPersistDay(List<TripLeg> legs) async {
    final updated = finalizeDayLegs(legs);
    for (final leg in updated) {
      await DatabaseService.updateTripLeg(leg);
    }
    return updated;
  }

  /// The legs belonging to the työmatka that ends with [last]: walk backwards
  /// through [allLegsAsc] (oldest first) until the leg that departed from
  /// home, inclusive.
  ///
  /// A trip is not a calendar date. Leaving home on Monday and returning on
  /// Tuesday is one työmatka spanning two dates, and its päivärahat depend on
  /// the whole span — which is exactly what the old per-date finalization
  /// could not see.
  static List<TripLeg> tripLegsEndingWith(
    List<TripLeg> allLegsAsc,
    TripLeg last,
    String home,
  ) {
    final endIndex = allLegsAsc.indexWhere((l) => l.id == last.id);
    if (endIndex < 0) return [last];

    var startIndex = endIndex;
    for (var i = endIndex; i >= 0; i--) {
      startIndex = i;
      final leg = allLegsAsc[i];
      if (leg.startLocation.trim().toLowerCase() == home.trim().toLowerCase()) {
        break;
      }
      // A gap this long is a new trip, not the same one: without this an
      // install whose history never contains a departure from home would
      // drag every leg it has ever recorded into one "trip".
      if (i > 0) {
        final previous = allLegsAsc[i - 1];
        final previousEnd = previous.endTime ?? previous.startTime;
        if (leg.startTime.difference(previousEnd) > const Duration(days: 7)) {
          break;
        }
      }
    }

    return allLegsAsc.sublist(startIndex, endIndex + 1);
  }

  /// The päivärahat a completed työmatka earns, one per travel day.
  ///
  /// [tripLegs] must be the whole trip (see [tripLegsEndingWith]), oldest
  /// first. A leg carrying a manual `dailyAllowanceType` overrides whatever
  /// the clock computed for the travel day starting on that leg's date —
  /// the driver's judgement wins, as it did before.
  List<DailyAllowance> allowancesForTrip(List<TripLeg> tripLegs) {
    if (tripLegs.isEmpty) return const [];

    final departure = tripLegs.first.startTime;
    final last = tripLegs.last;
    final returnAt = last.endTime;
    if (returnAt == null) return const [];

    final overridesByDate = <String, int>{};
    for (final leg in tripLegs) {
      final type = leg.dailyAllowanceType;
      if (type != null) overridesByDate[leg.date] = type;
    }

    final now = DateTime.now().toIso8601String();
    final days = travelDaysFor(departure, returnAt);

    return [
      for (final day in days)
        () {
          final override = overridesByDate[day.date];
          final type = override ?? (day.type == AllowanceType.full ? 2 : 1);
          return DailyAllowance(
            date: day.date,
            periodStart: day.start.toIso8601String(),
            type: type,
            amount: switch (type) {
              1 => allowance6h,
              2 => allowance10h,
              _ => 0.0,
            },
            createdAt: now,
          );
        }(),
    ];
  }

  /// Finalize a whole työmatka: per-leg values, working times, and one
  /// päiväraha per travel day written to the allowance table.
  ///
  /// Replaces the per-date finalization. The allowances are keyed by their
  /// travel day, so a middle day nobody drove still gets paid; each date's
  /// total is mirrored onto that date's last leg so the day view and the
  /// export keep reading what they always read.
  Future<List<TripLeg>> finalizeAndPersistTrip(List<TripLeg> tripLegs) async {
    if (tripLegs.isEmpty) return tripLegs;

    var updated = tripLegs.map((l) => calculateLeg(l)).toList();
    updated = _applyWorkingTimesPerDate(updated);

    final allowances = allowancesForTrip(updated);
    // Drop this trip's previous allowances first: an edited trip that now
    // earns fewer travel days must not leave the extra ones behind.
    await DatabaseService.deleteDailyAllowancesFrom(
      updated.first.startTime.toIso8601String(),
    );
    for (final allowance in allowances) {
      await DatabaseService.upsertDailyAllowance(allowance);
    }

    final totalByDate = <String, double>{};
    for (final allowance in allowances) {
      totalByDate[allowance.date] =
          (totalByDate[allowance.date] ?? 0) + allowance.amount;
    }

    updated = _mirrorAllowancesOntoLegs(updated, totalByDate);

    LogService().info(
      'Calc: finalized trip of ${updated.length} legs over '
      '${allowances.length} travel day(s), '
      '${allowances.fold<double>(0, (s, a) => s + a.amount)}€ päivärahaa',
    );

    for (final leg in updated) {
      await DatabaseService.updateTripLeg(leg);
    }
    return updated;
  }

  /// Working time is still a per-date notion (time at the work site that
  /// day), so it is computed per date within the trip.
  List<TripLeg> _applyWorkingTimesPerDate(List<TripLeg> legs) {
    final byDate = <String, List<TripLeg>>{};
    for (final leg in legs) {
      byDate.putIfAbsent(leg.date, () => []).add(leg);
    }
    final result = <String, TripLeg>{};
    for (final entry in byDate.entries) {
      for (final leg in calculateWorkingTimes(entry.value)) {
        result[_legKey(leg)] = leg;
      }
    }
    return legs.map((l) => result[_legKey(l)] ?? l).toList();
  }

  /// Put each date's päiväraha total on that date's last leg, and clear it
  /// from the others, so nothing is counted twice.
  ///
  /// This is a denormalised copy of the allowance table, kept because a leg
  /// row in Google Sheets has a päiväraha column and the sync sends legs one
  /// at a time. It is written here and nowhere else; the reports read
  /// [AllowanceLedger], which is the record, and which — unlike a column on a
  /// leg — can also speak for a travel day that has no legs at all.
  List<TripLeg> _mirrorAllowancesOntoLegs(
    List<TripLeg> legs,
    Map<String, double> totalByDate,
  ) {
    final lastLegKeyByDate = <String, String>{};
    for (final leg in legs) {
      lastLegKeyByDate[leg.date] = _legKey(leg);
    }
    return [
      for (final leg in legs)
        leg.copyWith(
          dailyAllowance: lastLegKeyByDate[leg.date] == _legKey(leg)
              ? (totalByDate[leg.date] ?? 0)
              : 0,
        ),
    ];
  }

  static String _legKey(TripLeg leg) =>
      '${leg.id ?? -1}|${leg.date}|${leg.legOrder}';

  /// Re-finalize whatever työmatka [date] belongs to.
  ///
  /// Editing a leg has to recompute the same thing recording it did, or the
  /// allowance table and the legs drift apart. When the trip containing this
  /// date has already returned home, the whole trip is finalized; when it
  /// has not, the day is finalized the old way — an unfinished trip has not
  /// earned a päiväraha yet, and cannot know how many travel days it will
  /// run to.
  Future<List<TripLeg>> refinalizeAroundDate(String date) async {
    final from = DateTime.now().subtract(const Duration(days: 30));
    final fromDate =
        '${from.year.toString().padLeft(4, '0')}-'
        '${from.month.toString().padLeft(2, '0')}-'
        '${from.day.toString().padLeft(2, '0')}';
    final candidates = await DatabaseService.getLegsFrom(fromDate);
    if (candidates.every((l) => l.date != date)) return const [];

    final closing = candidates.firstWhereOrNull(
      (l) =>
          l.endTime != null &&
          l.date.compareTo(date) >= 0 &&
          l.isReturnHomeTo(homeLocation),
    );
    if (closing == null) {
      return finalizeAndPersistDay(
        candidates.where((l) => l.date == date).toList(),
      );
    }
    return finalizeAndPersistTrip(
      tripLegsEndingWith(candidates, closing, homeLocation),
    );
  }

  /// Calculate a day summary: total km, total allowances.
  /// Returns [estimated] = true if any leg in the day is a draft.
  ({
    double totalKm,
    double totalKmAllowance,
    double totalDailyAllowance,
    double grandTotal,
    bool estimated,
  })
  summarizeDay(List<TripLeg> legs, {double? dailyAllowance}) {
    final totalKm = legs.fold<double>(0, (sum, l) => sum + l.kmDriven);
    final totalKmAllowance = legs.fold<double>(
      0,
      (sum, l) => sum + l.kmAllowance,
    );
    // Callers holding an [AllowanceLedger] pass the day's päiväraha in: it is
    // the record of what the travel days actually paid, where the figure
    // mirrored onto the legs is only a copy of it.
    final totalDailyAllowance =
        dailyAllowance ??
        legs.fold<double>(0, (sum, l) => sum + l.dailyAllowance);
    final hasDraft = legs.any((l) => l.isDraft);

    return (
      totalKm: double.parse(totalKm.toStringAsFixed(2)),
      totalKmAllowance: double.parse(totalKmAllowance.toStringAsFixed(2)),
      totalDailyAllowance: double.parse(totalDailyAllowance.toStringAsFixed(2)),
      grandTotal: double.parse(
        (totalKmAllowance + totalDailyAllowance).toStringAsFixed(2),
      ),
      estimated: hasDraft,
    );
  }
}
