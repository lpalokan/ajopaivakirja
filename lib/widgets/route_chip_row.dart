import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import '../models/route.dart' as model;

/// A horizontal chip row showing the user's most-used routes as shortcuts.
///
/// Placed just above the StartCard. Tapping a chip pre-fills the start
/// location + purpose on the parent's StartCard.
class RouteChipRow extends StatelessWidget {
  final List<model.Route> routes;
  final int? selectedRouteId;
  final ValueChanged<model.Route> onRouteSelected;
  final VoidCallback onShowAll;

  const RouteChipRow({
    super.key,
    required this.routes,
    this.selectedRouteId,
    required this.onRouteSelected,
    required this.onShowAll,
  });

  @override
  Widget build(BuildContext context) {
    if (routes.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: routes.length + 1, // +1 for "Kaikki reitit" link
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index < routes.length) {
            final route = routes[index];
            return RouteChip(
              route: route,
              isSelected: route.id == selectedRouteId,
              onTap: () => onRouteSelected(route),
            );
          }
          // "Kaikki reitit (N)" link
          return Center(
            child: TextButton(
              onPressed: onShowAll,
              child: Text(
                'Kaikki reitit (${routes.length})',
                style: TextStyle(color: colorScheme.primary),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Individual route chip: 120×64, name + meta line.
///
/// Selection cues are deliberately redundant: filled background, 2px primary
/// border, and a trailing check icon. All unselected chips share the same
/// neutral surface so position never reads as "highlighted".
class RouteChip extends StatelessWidget {
  final model.Route route;
  final bool isSelected;
  final VoidCallback onTap;

  const RouteChip({
    super.key,
    required this.route,
    this.isSelected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(12);

    return Material(
      color: isSelected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: isSelected
              ? colorScheme.primary
              : colorScheme.outlineVariant,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          width: 120,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      route.name,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isSelected)
                    Icon(
                      Symbols.check_circle,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${route.startLocation} → ${route.endLocation} · ${route.distanceKm.toStringAsFixed(1)} km',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
