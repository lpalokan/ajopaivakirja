import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:intl/intl.dart';
import '../models/trip_leg.dart';
import '../models/expense.dart';
import '../services/database_service.dart';
import '../main.dart';
import 'odometer_dialog.dart';
import 'expense_dialog.dart';
import '../services/odometer_vision_service.dart';

/// Full-bleed hero card for an active (in-progress) trip.
///
/// Renders a gradient surface, oversized live distance counter, and a
/// pulse dot. An overflow menu houses _Kulu_ and _Peru matka_.
class ActiveTripCard extends StatelessWidget {
  final TripLeg leg;
  final double liveDistanceKm;
  final Future<void> Function(
    int odometer, {
    DateTime? endTime,
    String? endLocation,
    String? purpose,
  })
  onStopDriving;
  final VoidCallback? onCancel;
  final OdometerVisionService? visionService;

  const ActiveTripCard({
    super.key,
    required this.leg,
    this.liveDistanceKm = 0,
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
    final routeLabel =
        leg.routeDescription ??
        '${leg.startLocation} → ${leg.endLocation ?? '...'}';

    final numeralLarge = Theme.of(
      context,
    ).extension<NumeralTypography>()!.large;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary,
            Color.lerp(colorScheme.primary, Colors.black, 0.2)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with route label + overflow menu
          Row(
            children: [
              _LivePulse(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ajo käynnissä',
                      style: TextStyle(
                        color: colorScheme.onPrimary.withAlpha(200),
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      routeLabel,
                      style: TextStyle(
                        color: colorScheme.onPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                iconColor: colorScheme.onPrimary.withAlpha(200),
                onSelected: (value) {
                  if (value == 'expense') {
                    _addExpense(context);
                  } else if (value == 'cancel') {
                    _cancelDriving(context);
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'expense',
                    child: ListTile(
                      leading: Icon(Symbols.receipt_long),
                      title: Text('Kulu'),
                      dense: true,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'cancel',
                    child: ListTile(
                      leading: Icon(Symbols.close, color: Colors.red),
                      title: Text(
                        'Peru matka',
                        style: TextStyle(color: Colors.red),
                      ),
                      dense: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Live distance counter
          Center(
            child: Text(
              '${(leg.kmDriven + liveDistanceKm).toStringAsFixed(1)} km',
              style: numeralLarge.copyWith(color: colorScheme.onPrimary),
            ),
          ),
          const SizedBox(height: 4),
          // Start time + duration
          Center(
            child: Text(
              'Lähtö $startTime · $durationStr',
              style: TextStyle(
                color: colorScheme.onPrimary.withAlpha(180),
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // In-card CTA
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: () => _stopDriving(context),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.onPrimary.withAlpha(30),
                foregroundColor: colorScheme.onPrimary,
              ),
              child: const Text('Olen perillä'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addExpense(BuildContext context) async {
    final result =
        await showDialog<
          ({ExpenseType type, double amount, String? description})
        >(context: context, builder: (ctx) => const ExpenseDialog());
    if (result != null && leg.id != null) {
      await DatabaseService.insertExpense(
        Expense(
          tripLegId: leg.id,
          type: result.type,
          amount: result.amount,
          description: result.description,
          createdAt: DateTime.now().toIso8601String(),
        ),
      );
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
        content: const Text(
          'Haluatko varmasti peruuttaa käynnissä olevan matkan?',
        ),
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

/// Animated pulse dot indicating a live trip.
class _LivePulse extends StatefulWidget {
  @override
  State<_LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<_LivePulse>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Colors.greenAccent,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
