import '../models/route.dart';
import 'location_service.dart';

/// The routes the driver can start from where they are standing.
///
/// A route's start is a free-text place name ("Koti", "Työ"), so "near me" is
/// answered through the known-location table: a route is nearby when its
/// start name is one of the [matches] — the zones within
/// [LocationService.nearbyMatchRadiusMeters] of the current fix.
///
/// Ordered by how close that start is, most recently driven first among
/// equals, so the top shortcut is the one for the spot the driver is actually
/// standing on.
List<Route> routesStartingNear(
  List<Route> routes,
  List<ZoneMatch> matches, {
  int limit = 2,
}) {
  if (routes.isEmpty || matches.isEmpty) return const [];

  // `matches` arrives nearest-first, so the first entry for a name wins.
  final distanceByPlace = <String, double>{};
  for (final match in matches) {
    distanceByPlace.putIfAbsent(
      match.zone.name.trim().toLowerCase(),
      () => match.distanceMeters,
    );
  }

  double? distanceOf(Route route) =>
      distanceByPlace[route.startLocation.trim().toLowerCase()];

  final nearby = routes.where((r) => distanceOf(r) != null).toList()
    ..sort((a, b) {
      final byDistance = distanceOf(a)!.compareTo(distanceOf(b)!);
      if (byDistance != 0) return byDistance;
      return b.updatedAt.compareTo(a.updatedAt);
    });

  return nearby.take(limit).toList();
}
