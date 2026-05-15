import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/trip_leg.dart';
import 'odometer_dialog.dart';

/// Shared widget showing the currently active (in-progress) trip.
/// Used by both [HomeScreen] and [RouteManagementScreen].
class ActiveTripCard extends StatelessWidget {
  final TripLeg leg;
  final Future<void> Function(int odometer, {DateTime? endTime}) onStopDriving;

  const ActiveTripCard({
    super.key,
    required this.leg,
    required this.onStopDriving,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final startTime = DateFormat('HH:mm').format(leg.startTime);
    final duration = DateTime.now().difference(leg.startTime);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final durationStr = '$hours h ${minutes.toString().padLeft(2, '0')} min';
    final expectedOdometer = leg.startOdometer + leg.kmDriven.toInt();

    return Card(
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.directions_car,
                    color: colorScheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ajo käynnissä',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        leg.routeDescription ??
                            '${leg.startLocation} → ${leg.endLocation}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Lähtö: $startTime'),
                Text('Kesto: $durationStr'),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Mittari lähtiessä: ${leg.startOdometer} km'),
                Text('Arvioitu perillä: $expectedOdometer km'),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _stopDriving(context),
                icon: const Icon(Icons.flag),
                label: const Text('Olen perillä'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _stopDriving(BuildContext context) async {
    final expectedOdometer = leg.startOdometer + leg.kmDriven.toInt();
    final result = await showOdometerDialog(
      context: context,
      title: 'Olen perillä',
      subtitle: 'Kohde: ${leg.endLocation ?? leg.routeDescription}',
      label: 'Matkamittari perillä (km)',
      actionLabel: 'Lopeta ajo',
      initialValue: expectedOdometer,
      expectedHint: expectedOdometer,
      showTime: true,
      initialTime: DateTime.now(),
      timeLabel: 'Päättymisaika',
    );
    if (result != null) {
      await onStopDriving(result.odometer, endTime: result.time);
    }
  }
}
