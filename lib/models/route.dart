class Route {
  final int? id;
  final String name;
  final String startLocation;
  final String endLocation;
  final double distanceKm;
  final String? lastPurpose;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Route({
    this.id,
    required this.name,
    required this.startLocation,
    required this.endLocation,
    required this.distanceKm,
    this.lastPurpose,
    required this.createdAt,
    required this.updatedAt,
  });

  Route copyWith({
    int? id,
    String? name,
    String? startLocation,
    String? endLocation,
    double? distanceKm,
    String? lastPurpose,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Route(
      id: id ?? this.id,
      name: name ?? this.name,
      startLocation: startLocation ?? this.startLocation,
      endLocation: endLocation ?? this.endLocation,
      distanceKm: distanceKm ?? this.distanceKm,
      lastPurpose: lastPurpose ?? this.lastPurpose,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'start_location': startLocation,
      'end_location': endLocation,
      'distance_km': distanceKm,
      'last_purpose': lastPurpose,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Route.fromMap(Map<String, dynamic> map) {
    return Route(
      id: map['id'] as int?,
      name: map['name'] as String,
      startLocation: map['start_location'] as String,
      endLocation: map['end_location'] as String,
      distanceKm: (map['distance_km'] as num).toDouble(),
      lastPurpose: map['last_purpose'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => toMap();

  factory Route.fromJson(Map<String, dynamic> json) => Route.fromMap(json);

  @override
  String toString() =>
      'Route(id: $id, name: $name, $startLocation ↔ $endLocation, ${distanceKm}km)';
}
