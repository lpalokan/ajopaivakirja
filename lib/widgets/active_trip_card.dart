import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/trip_leg.dart';
import '../models/expense.dart';
import '../services/database_service.dart';
import 'odometer_dialog.dart';
import 'expense_dialog.dart';
import '../services/odometer_vision_service.dart';

/// Shared widget showing the currently active (in-progress) trip.
/// Used by both [HomeScreen] and [RouteManagementScreen].
class ActiveTripCard extends StatelessWidget {
  final TripLeg leg;
  final Future<void> Function(
    int odometer, {
    DateTime? endTime,
    String? endLocation,
    String? purpose,
  }) onStopDriving;
  final VoidCallback? onCancel;
  final OdometerVisionService? visionService;

  const ActiveTripCard({
    super.key,
    required this.leg,
    required this.onStopDriving,
    this.onCancel,
    this.visionService,
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
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _stopDriving(context),
                    icon: const Icon(Icons.flag),
                    label: const Text('Olen perillä'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _addExpense(context),
                  icon: const Icon(Icons.receipt_long, size: 20),
                  label: const Text('Kulu'),
                ),
              ],
            ),
            if (onCancel != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => _cancelDriving(context),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Peru matka'),
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.error,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _addExpense(BuildContext context) async {
    final result = await showDialog<({ExpenseType type, double amount, String? description})>(
      context: context,
      builder: (ctx) => const ExpenseDialog(),
    );
    if (result != null && leg.id != null) {
      await DatabaseService.insertExpense(Expense(
        tripLegId: leg.id,
        type: result.type,
        amount: result.amount,
        description: result.description,
        createdAt: DateTime.now().toIso8601String(),
      ));
    }
  }

  Future<void> _stopDriving(BuildContext context) async {
    final isAdHoc = leg.routeId == null && leg.routeDescription == null;
    final expectedOdometer = leg.startOdometer + leg.kmDriven.toInt();

    List<String> suggestions = const [];
    if (isAdHoc) {
      try {
        suggestions = await DatabaseService.getUniqueLocations();
      } catch (_) {}
    }
    if (!context.mounted) return;

    final result = await showOdometerDialog(
      context: context,
      title: 'Olen perillä',
      subtitle: isAdHoc
          ? 'Lähtö: ${leg.startLocation}'
          : 'Kohde: ${leg.endLocation ?? leg.routeDescription}',
      label: 'Matkamittari perillä (km)',
      actionLabel: 'Lopeta ajo',
      initialValue: isAdHoc ? null : expectedOdometer,
      expectedHint: isAdHoc ? null : expectedOdometer,
      showTime: true,
      initialTime: DateTime.now(),
      timeLabel: 'Päättymisaika',
      locationLabel: isAdHoc ? 'Määränpää' : null,
      locationSuggestions: suggestions,
      relatedField: isAdHoc ? 'Tarkoitus' : null,
      initialPurpose: isAdHoc ? leg.purpose : null,
      visionService: visionService,
    );
    if (result != null) {
      await onStopDriving(
        result.odometer,
        endTime: result.time,
        endLocation: result.location,
        purpose: result.purpose,
      );
    }
  }

  Future<void> _cancelDriving(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Peru matka'),
        content: const Text('Haluatko varmasti peruuttaa käynnissä olevan matkan?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Ei'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Peru'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      onCancel?.call();
    }
  }
}
