import '../models/trip_leg.dart';
import '../models/app_settings.dart';
import 'database_service.dart';

class TripCalculator {
  final AppSettings _settings;

  TripCalculator(this._settings);

  double get kmRate => _settings.kmRate;
  double get allowance6h => _settings.allowance6h;
  double get allowance10h => _settings.allowance10h;
  String get homeLocation => _settings.homeLocation;

  /// Calculate values for a single leg.
  TripLeg calculateLeg(TripLeg leg) {
    final kmDriven = (leg.endOdometer ?? leg.startOdometer) - leg.startOdometer;
    final kmAllowance = kmDriven * kmRate;
    final legDurationHours = leg.endTime != null
        ? leg.endTime!.difference(leg.startTime).inMinutes / 60.0
        : 0.0;
    final isReturnHome = _isReturningHome(leg.endLocation);

    return leg.copyWith(
      kmDriven: kmDriven.toDouble(),
      kmAllowance: double.parse(kmAllowance.toStringAsFixed(2)),
      legDurationHours: double.parse(legDurationHours.toStringAsFixed(2)),
      isReturnHome: isReturnHome,
    );
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

  /// Calculate working time for each leg.
  /// Working time = gap between this leg's end_time and next leg's start_time.
  /// If destination is home, working time = 0.
  List<TripLeg> calculateWorkingTimes(List<TripLeg> legs) {
    final updated = <TripLeg>[];
    for (var i = 0; i < legs.length; i++) {
      final leg = legs[i];
      double workingTime = 0;

      if (i < legs.length - 1) {
        final nextLeg = legs[i + 1];
        if (leg.endTime != null) {
          workingTime =
              nextLeg.startTime.difference(leg.endTime!).inMinutes / 60.0;
        }
      }

      if (leg.isReturnHome) {
        workingTime = 0;
      }

      workingTime = double.parse(workingTime.toStringAsFixed(2));
      updated.add(leg.copyWith(workingTimeHours: workingTime));
    }
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
    if (last.dailyAllowanceType != null) {
      allowance = switch (last.dailyAllowanceType) {
        1 => allowance6h,
        2 => allowance10h,
        _ => 0,
      };
    } else {
      allowance = calculateDailyAllowance(updated).allowance;
    }

    // Apply daily allowance to the last leg (returning home)
    if (last.isReturnHome) {
      updated[updated.length - 1] = last.copyWith(
        dailyAllowance: allowance,
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
