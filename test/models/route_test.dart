import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/models/route.dart';

void main() {
  Route sample() => Route(
        id: 5,
        name: 'Töihin',
        startLocation: 'Koti',
        endLocation: 'Työ',
        distanceKm: 54.0,
        lastPurpose: 'Asiakastapaaminen',
        createdAt: DateTime(2026, 1, 2, 10, 0),
        updatedAt: DateTime(2026, 5, 16, 8, 30),
      );

  test('toMap/fromMap round-trips and preserves DateTime', () {
    final restored = Route.fromMap(sample().toMap());
    expect(restored.id, 5);
    expect(restored.name, 'Töihin');
    expect(restored.startLocation, 'Koti');
    expect(restored.endLocation, 'Työ');
    expect(restored.distanceKm, 54.0);
    expect(restored.lastPurpose, 'Asiakastapaaminen');
    expect(restored.createdAt, DateTime(2026, 1, 2, 10, 0));
    expect(restored.updatedAt, DateTime(2026, 5, 16, 8, 30));
  });

  test('fromMap accepts integer distance as double', () {
    final map = sample().toMap()..['distance_km'] = 54;
    expect(Route.fromMap(map).distanceKm, 54.0);
  });

  test('copyWith overrides only provided fields', () {
    final updated = sample().copyWith(distanceKm: 60);
    expect(updated.distanceKm, 60);
    expect(updated.name, 'Töihin');
  });
}
