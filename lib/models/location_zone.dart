class LocationZone {
  final int? id;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final String createdAt;

  const LocationZone({
    this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 200,
    required this.createdAt,
  });

  LocationZone copyWith({
    int? id,
    String? name,
    double? latitude,
    double? longitude,
    double? radiusMeters,
    String? createdAt,
  }) {
    return LocationZone(
      id: id ?? this.id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'radius_meters': radiusMeters,
      'created_at': createdAt,
    };
  }

  factory LocationZone.fromMap(Map<String, dynamic> map) {
    return LocationZone(
      id: map['id'] as int?,
      name: map['name'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      radiusMeters: (map['radius_meters'] as num?)?.toDouble() ?? 200,
      createdAt: map['created_at'] as String,
    );
  }

  @override
  String toString() =>
      'LocationZone(id: $id, $name, ($latitude, $longitude), ${radiusMeters}m)';
}
