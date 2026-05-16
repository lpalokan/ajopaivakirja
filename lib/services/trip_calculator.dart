import '../models/trip_leg.dart';
import '../models/app_settings.dart';
import 'database_service.dart';
import 'log_service.dart';

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
    final isReturnHome = _isReturningHome(leg.endLocation);

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

  bool _isReturningHome(String? endLocation) {
    if (endLocation == null) return false;
    return endLocation.trim().toLowerCase() ==
        _settings.homeLocation.trim().toLowerCase();
  }

  /// Calculate daily allowance for a list of legs on the same date.
  /// Returns the daily allowance amount and total hours away.
  ({double allowance, double totalHours}) calculateDailyAllowance(
      List<TripLeg> legs) {
    if (legs.isEmpty) return (allowance: 0, totalHours: 0);

    final firstStart = legs.first.startTime;
    final lastEnd = legs.last.endTime ?? legs.last.startTime;

    final totalHours =
        lastEnd.difference(firstStart).inMinutes / 60.0;

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

    double totalWorkingTime = 0;
    if (firstEnd != null) {
      totalWorkingTime = lastStart.difference(firstEnd).inMinutes / 60.0;
    }

    // Put total working time on the last leg
    updated[updated.length - 1] = updated.last.copyWith(
      workingTimeHours: double.parse(totalWorkingTime.toStringAsFixed(2)),
    );

    return updated;
  }

  /// Finalize a day's legs: calculate all values, apply daily allowance to
  /// the last leg (returning home), and update working times.
  Future<List<TripLeg>> finalizeDay(List<TripLeg> legs) async {
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
    LogService().info('Calc: finalizeDay ${updated.length} legs, allowance=$allowance€ ($mode)');

    // Apply daily allowance to the last leg if returning home or override is set
    if (last.isReturnHome || last.dailyAllowanceType != null) {
      updated[updated.length - 1] = last.copyWith(
        dailyAllowance: allowance,
      );
    }

    // Calculate total day hours and place on last leg
    if (last.endTime != null) {
      final totalHours = last.endTime!
          .difference(updated.first.startTime)
          .inMinutes / 60.0;
      updated[updated.length - 1] = updated.last.copyWith(
        legDurationHours: double.parse(totalHours.toStringAsFixed(2)),
      );
    }

    // Save updated legs to database
    for (final leg in updated) {
      await DatabaseService.updateTripLeg(leg);
    }

    return updated;
  }

  /// Calculate a day summary: total km, total allowances.
  ({double totalKm, double totalKmAllowance, double totalDailyAllowance,
      double grandTotal}) summarizeDay(List<TripLeg> legs) {
    final totalKm = legs.fold<double>(0, (sum, l) => sum + l.kmDriven);
    final totalKmAllowance =
        legs.fold<double>(0, (sum, l) => sum + l.kmAllowance);
    final totalDailyAllowance =
        legs.fold<double>(0, (sum, l) => sum + l.dailyAllowance);

    return (
      totalKm: double.parse(totalKm.toStringAsFixed(2)),
      totalKmAllowance: double.parse(totalKmAllowance.toStringAsFixed(2)),
      totalDailyAllowance:
          double.parse(totalDailyAllowance.toStringAsFixed(2)),
      grandTotal: double.parse(
          (totalKmAllowance + totalDailyAllowance).toStringAsFixed(2)),
    );
  }
}
