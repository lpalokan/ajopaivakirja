import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/route.dart';
import '../services/database_service.dart';

class RouteNotifier extends StateNotifier<List<Route>> {
  RouteNotifier() : super([]);

  Future<void> load() async {
    state = await DatabaseService.getAllRoutes();
  }

  Future<void> add(Route route) async {
    final saved = await DatabaseService.insertRoute(route);
    state = [saved, ...state];
  }

  Future<void> update(Route route) async {
    final updated = route.copyWith(updatedAt: DateTime.now());
    await DatabaseService.updateRoute(updated);
    state = state.map((r) => r.id == route.id ? updated : r).toList();
  }

  Future<void> remove(int id) async {
    await DatabaseService.deleteRoute(id);
    state = state.where((r) => r.id != id).toList();
  }

  Future<void> savePurpose(int routeId, String purpose) async {
    await DatabaseService.updateRouteLastPurpose(routeId, purpose);
    final updated = state
        .firstWhere((r) => r.id == routeId)
        .copyWith(lastPurpose: purpose);
    state = state.map((r) => r.id == routeId ? updated : r).toList();
  }

  Future<void> markUsed(int routeId) async {
    await DatabaseService.updateRouteTimestamp(routeId);
  }

  List<Route> getRecentRoutes({int limit = 2}) {
    final sorted = List<Route>.from(state)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sorted.take(limit).toList();
  }

  List<Route> routesContaining(String location) {
    final loc = location.trim().toLowerCase();
    return state.where((r) {
      return r.startLocation.trim().toLowerCase() == loc ||
          r.endLocation.trim().toLowerCase() == loc;
    }).toList();
  }
}

final routeProvider = StateNotifierProvider<RouteNotifier, List<Route>>((ref) {
  return RouteNotifier();
});
