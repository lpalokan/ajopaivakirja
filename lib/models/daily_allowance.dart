/// One travel day's päiväraha, stored in its own right rather than hung off a
/// leg.
///
/// A työmatka is measured in 24-hour travel days from departure, so a travel
/// day can fall on a date with no driving at all — the middle day of a
/// three-day trip. Such a day still earns a full päiväraha, and there is no
/// leg to attach it to, which is why these are their own records.
class DailyAllowance {
  final int? id;

  /// Calendar date the travel day begins on, `yyyy-MM-dd`. What the day view
  /// and the export group by.
  final String date;

  /// ISO-8601 start of the 24-hour period. The natural identity of a travel
  /// day, and what makes re-finalizing a trip idempotent.
  final String periodStart;

  /// 1 = osapäiväraha (half), 2 = kokopäiväraha (full). Same encoding as
  /// `TripLeg.dailyAllowanceType`, so a manual override and a computed
  /// allowance speak one language.
  final int type;

  final double amount;
  final String createdAt;

  const DailyAllowance({
    this.id,
    required this.date,
    required this.periodStart,
    required this.type,
    required this.amount,
    required this.createdAt,
  });

  bool get isFull => type == 2;
  bool get isHalf => type == 1;

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'date': date,
    'period_start': periodStart,
    'type': type,
    'amount': amount,
    'created_at': createdAt,
  };

  factory DailyAllowance.fromMap(Map<String, dynamic> map) => DailyAllowance(
    id: map['id'] as int?,
    date: map['date'] as String,
    periodStart: map['period_start'] as String,
    type: map['type'] as int,
    amount: (map['amount'] as num).toDouble(),
    createdAt: map['created_at'] as String,
  );

  @override
  String toString() =>
      'DailyAllowance($date, ${isFull ? 'full' : 'half'}, $amount€)';
}
