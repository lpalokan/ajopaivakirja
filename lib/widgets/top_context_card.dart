import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import '../models/route.dart' as model;

/// Top-of-screen card shown when a route chip is selected. Confirms what
/// "Aloita ajo" will do before the user commits, and uses the screen real
/// estate that would otherwise be empty above the chip row.
class RoutePreviewCard extends StatelessWidget {
  final model.Route route;
  final ValueListenable<int?> odometerListenable;

  const RoutePreviewCard({
    super.key,
    required this.route,
    required this.odometerListenable,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final distanceKm = route.distanceKm;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Symbols.route, size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  'Valittu reitti',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              route.name,
              style: theme.textTheme.headlineSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              '${route.startLocation}  →  ${route.endLocation}  ·  ${distanceKm.toStringAsFixed(1)} km',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<int?>(
              valueListenable: odometerListenable,
              builder: (context, odo, _) {
                if (odo == null) {
                  return Text(
                    'Mittari nyt — syötä lukema alta',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  );
                }
                final expectedEnd = odo + distanceKm.round();
                return Text(
                  'Mittari nyt $odo → arviolta $expectedEnd',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                );
              },
            ),
            if (route.lastPurpose != null && route.lastPurpose!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Edellinen tarkoitus: ${route.lastPurpose}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Top-of-screen card shown when no route is selected and no trips have
/// been logged today. Sets the user's expectation that the start button
/// will begin an unstructured trip.
class AdHocCard extends StatelessWidget {
  const AdHocCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Symbols.directions_car,
                  size: 20,
                  color: colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Vapaa ajo',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Aloita mittarilukemasta. Reitti tallentuu kun saavut perille.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
