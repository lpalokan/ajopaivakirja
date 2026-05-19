enum TripStatus { active, draft, completed }

class TripLeg {
  final int? id;
  final String date;
  final int legOrder;
  final int? routeId;
  final DateTime startTime;
  final DateTime? endTime;
  final int startOdometer;
  final int? endOdometer;
  final String startLocation;
  final String? endLocation;
  final String? routeDescription;
  final double kmDriven;
  final double workingTimeHours;
  final double legDurationHours;
  final String? purpose;
  final String driver;
  final double kmAllowance;
  final double dailyAllowance;
  final int? dailyAllowanceType;
  final bool isReturnHome;
  final bool synced;

  const TripLeg({
    this.id,
    required this.date,
    required this.legOrder,
    this.routeId,
    required this.startTime,
    this.endTime,
    required this.startOdometer,
    this.endOdometer,
    required this.startLocation,
    this.endLocation,
    this.routeDescription,
    this.kmDriven = 0,
    this.workingTimeHours = 0,
    this.legDurationHours = 0,
    this.purpose,
    required this.driver,
    this.kmAllowance = 0,
    this.dailyAllowance = 0,
    this.dailyAllowanceType,
    this.isReturnHome = false,
    this.synced = false,
  });

  TripLeg copyWith({
    int? id,
    String? date,
    int? legOrder,
    int? routeId,
    DateTime? startTime,
    DateTime? endTime,
    int? startOdometer,
    int? endOdometer,
    String? startLocation,
    String? endLocation,
    String? routeDescription,
    double? kmDriven,
    double? workingTimeHours,
    double? legDurationHours,
    String? purpose,
    String? driver,
    double? kmAllowance,
    double? dailyAllowance,
    int? dailyAllowanceType = _allowanceTypeSentinel,
    bool? isReturnHome,
    bool? synced,
  }) {
    return TripLeg(
      id: id ?? this.id,
      date: date ?? this.date,
      legOrder: legOrder ?? this.legOrder,
      routeId: routeId ?? this.routeId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      startOdometer: startOdometer ?? this.startOdometer,
      endOdometer: endOdometer ?? this.endOdometer,
      startLocation: startLocation ?? this.startLocation,
      endLocation: endLocation ?? this.endLocation,
      routeDescription: routeDescription ?? this.routeDescription,
      kmDriven: kmDriven ?? this.kmDriven,
      workingTimeHours: workingTimeHours ?? this.workingTimeHours,
      legDurationHours: legDurationHours ?? this.legDurationHours,
      purpose: purpose ?? this.purpose,
      driver: driver ?? this.driver,
      kmAllowance: kmAllowance ?? this.kmAllowance,
      dailyAllowance: dailyAllowance ?? this.dailyAllowance,
      dailyAllowanceType: identical(dailyAllowanceType, _allowanceTypeSentinel)
          ? this.dailyAllowanceType
          : dailyAllowanceType,
      isReturnHome: isReturnHome ?? this.isReturnHome,
      synced: synced ?? this.synced,
    );
  }

  static const _allowanceTypeSentinel = -999;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'date': date,
      'leg_order': legOrder,
      'route_id': routeId,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'start_odometer': startOdometer,
      'end_odometer': endOdometer,
      'start_location': startLocation,
      'end_location': endLocation,
      'route_description': routeDescription,
      'km_driven': kmDriven,
      'working_time_hours': workingTimeHours,
      'leg_duration_hours': legDurationHours,
      'purpose': purpose,
      'driver': driver,
      'km_allowance': kmAllowance,
      'daily_allowance': dailyAllowance,
      'daily_allowance_type': dailyAllowanceType,
      'is_return_home': isReturnHome ? 1 : 0,
      'synced': synced ? 1 : 0,
    };
  }

  factory TripLeg.fromMap(Map<String, dynamic> map) {
    return TripLeg(
      id: map['id'] as int?,
      date: map['date'] as String,
      legOrder: map['leg_order'] as int,
      routeId: map['route_id'] as int?,
      startTime: DateTime.parse(map['start_time'] as String),
      endTime: map['end_time'] != null
          ? DateTime.parse(map['end_time'] as String)
          : null,
      startOdometer: map['start_odometer'] as int,
      endOdometer: map['end_odometer'] as int?,
      startLocation: map['start_location'] as String,
      endLocation: map['end_location'] as String?,
      routeDescription: map['route_description'] as String?,
      kmDriven: (map['km_driven'] as num?)?.toDouble() ?? 0,
      workingTimeHours: (map['working_time_hours'] as num?)?.toDouble() ?? 0,
      legDurationHours: (map['leg_duration_hours'] as num?)?.toDouble() ?? 0,
      purpose: map['purpose'] as String?,
      driver: map['driver'] as String,
      kmAllowance: (map['km_allowance'] as num?)?.toDouble() ?? 0,
      dailyAllowance: (map['daily_allowance'] as num?)?.toDouble() ?? 0,
      dailyAllowanceType: map['daily_allowance_type'] as int?,
      isReturnHome: (map['is_return_home'] as int?) == 1,
      synced: (map['synced'] as int?) == 1,
    );
  }

  Map<String, dynamic> toJson() => toMap();

  factory TripLeg.fromJson(Map<String, dynamic> json) => TripLeg.fromMap(json);

  double get totalAllowance => kmAllowance + dailyAllowance;

  /// Derived status. Requires [activeLegId] to distinguish the currently
  /// running trip from an abandoned one — both have null end fields but only
  /// the one matching [activeLegId] is truly active.
  TripStatus status({int? activeLegId}) {
    if (activeLegId != null && id == activeLegId) return TripStatus.active;
    if (endOdometer == null || endLocation == null || endLocation!.isEmpty) {
      return TripStatus.draft;
    }
    return TripStatus.completed;
  }

  /// Whether this leg is a fully-completed trip ready for export.
  bool get isCompleted =>
      endOdometer != null && endLocation != null && endLocation!.isNotEmpty;

  /// Whether this leg is a draft (started but incomplete).
  bool get isDraft => !isCompleted;

  /// Whether this leg is an active in-progress trip.
  /// Must be compared against the current active-leg id externally.
  bool get isActive => false;

  @override
  String toString() =>
      'TripLeg(id: $id, $date #$legOrder, $startLocation → $endLocation)';
}
