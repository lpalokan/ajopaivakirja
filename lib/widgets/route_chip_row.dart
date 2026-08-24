import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import '../models/route.dart' as model;

/// A full-width row of route shortcut buttons.
///
/// Placed just above the StartCard. Tapping a button pre-fills the start
/// location + purpose on the parent's StartCard. The home view passes two
/// routes: one fills the full width, two split it evenly.
///
/// [title] names which two they are ("Lähellä" when they were picked by GPS
/// proximity, "Viimeksi ajetut" when the position is unknown and the list
/// fell back to recency). Without it a nearby list with one entry is
/// indistinguishable from a bug.
class RouteChipRow extends StatelessWidget {
  final List<model.Route> routes;
  final int? selectedRouteId;
  final ValueChanged<model.Route> onRouteSelected;
  final String? title;

  const RouteChipRow({
    super.key,
    required this.routes,
    this.selectedRouteId,
    required this.onRouteSelected,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    if (routes.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              for (var i = 0; i < routes.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: RouteChip(
                    route: routes[i],
                    isSelected: routes[i].id == selectedRouteId,
                    onTap: () => onRouteSelected(routes[i]),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Individual route button: fills its share of the row, ~92px tall, with the
/// name + meta line.
///
/// Selection cues are deliberately redundant: filled background, 2px primary
/// border, and a trailing check icon. All unselected buttons share the same
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
          color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          height: 92,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      route.name,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isSelected)
                    Icon(
                      Symbols.check_circle,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${route.startLocation} → ${route.endLocation} · ${route.distanceKm.toStringAsFixed(1)} km',
                style: TextStyle(
                  fontSize: 12,
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
