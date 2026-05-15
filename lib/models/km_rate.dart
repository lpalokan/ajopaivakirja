class KmRate {
  final int year;
  final double rate;

  const KmRate({required this.year, required this.rate});

  KmRate copyWith({int? year, double? rate}) {
    return KmRate(
      year: year ?? this.year,
      rate: rate ?? this.rate,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'year': year,
      'rate': rate,
    };
  }

  factory KmRate.fromMap(Map<String, dynamic> map) {
    return KmRate(
      year: map['year'] as int,
      rate: (map['rate'] as num).toDouble(),
    );
  }

  /// Known Finnish km rates per year (Verohallinto).
  static const Map<int, double> finnishDefaults = {
    2020: 0.43,
    2021: 0.44,
    2022: 0.46,
    2023: 0.53,
    2024: 0.57,
    2025: 0.57,
  };

  @override
  String toString() => 'KmRate($year: ${rate.toStringAsFixed(2)}€)';
}
