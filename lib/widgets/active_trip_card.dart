import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:intl/intl.dart';
import '../models/trip_leg.dart';
import '../models/expense.dart';
import '../services/database_service.dart';
import '../main.dart';
import '../providers/trip_provider.dart';
import 'expense_dialog.dart';

/// Full-bleed hero card for an active (in-progress) trip.
///
/// Renders a gradient surface, oversized live distance counter, and a
/// pulse dot. An overflow menu houses _Kulu_ and _Peru matka_.
///
/// The card calls [TripNotifier.stopTrip] / [TripNotifier.cancelTrip]
/// directly via Riverpod — it no longer receives callback props.
///
/// Accessibility (issue #46):
/// - A1: the "Olen perillä" CTA uses a solid surface, not a translucent
///   white-on-gradient — readable as a discrete shape ≥ 13:1 against the
///   gradient.
/// - A3: the whole card exposes a Semantics container so TalkBack announces
///   "Ajo käynnissä, X kilometriä" instead of ungrouped fragments.
/// - A5: muted text uses `SemanticColors.onPrimaryMuted` (an explicit colour)
///   rather than opacity, so its contrast is computable.
/// - A6: long-press on the counter freezes the displayed value and the
///   pulse animation (WCAG 2.2.2); tap to resume.
class ActiveTripCard extends ConsumerStatefulWidget {
  final TripLeg leg;

  const ActiveTripCard({super.key, required this.leg});

  @override
  ConsumerState<ActiveTripCard> createState() => _ActiveTripCardState();
}

class _ActiveTripCardState extends ConsumerState<ActiveTripCard> {
  /// When non-null, the counter and pulse are paused — the displayed value
  /// is frozen at this snapshot. Tap to clear and resume live updates.
  double? _frozenDistanceKm;

  late final ValueNotifier<double> _liveDistance;

  @override
  void initState() {
    super.initState();
    _liveDistance = ref.read(tripProvider.notifier).liveDistanceKm;
    _liveDistance.addListener(_onLiveDistanceChanged);
  }

  @override
  void dispose() {
    _liveDistance.removeListener(_onLiveDistanceChanged);
    super.dispose();
  }

  void _onLiveDistanceChanged() {
    if (mounted) setState(() {});
  }

  void _toggleFreeze() {
    setState(() {
      if (_frozenDistanceKm == null) {
        _frozenDistanceKm = widget.leg.kmDriven + _liveDistance.value;
      } else {
        _frozenDistanceKm = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final semColors = Theme.of(context).extension<SemanticColors>()!;
    final startTime = DateFormat('HH:mm').format(widget.leg.startTime);
    final duration = DateTime.now().difference(widget.leg.startTime);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final durationStr = '$hours h ${minutes.toString().padLeft(2, '0')} min';
    final routeLabel =
        widget.leg.routeDescription ??
        '${widget.leg.startLocation} → ${widget.leg.endLocation ?? '...'}';

    final numeralLarge = Theme.of(
      context,
    ).extension<NumeralTypography>()!.large;

    final liveKm = widget.leg.kmDriven + _liveDistance.value;
    final displayedKm = _frozenDistanceKm ?? liveKm;
    final displayedKmStr = '${displayedKm.toStringAsFixed(1)} km';
    final isPinned = _frozenDistanceKm != null;

    return Semantics(
      container: true,
      label: 'Ajo käynnissä, ${displayedKm.toStringAsFixed(1)} kilometriä',
      child: Container(
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
                _LivePulse(paused: isPinned),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ajo käynnissä',
                        style: TextStyle(
                          color: semColors.onPrimaryMuted,
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
                  tooltip: 'Lisää toimintoja',
                  iconColor: semColors.onPrimaryMuted,
                  onSelected: (value) {
                    if (value == 'expense') {
                      _addExpense(context);
                    } else if (value == 'cancel') {
                      ref.read(tripProvider.notifier).cancelTrip(context);
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
            // Live distance counter — long-press freezes (A6 · WCAG 2.2.2).
            Center(
              child: GestureDetector(
                onLongPress: _toggleFreeze,
                onTap: isPinned ? _toggleFreeze : null,
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayedKmStr,
                      key: const ValueKey('active-trip-counter'),
                      style: numeralLarge.copyWith(
                        color: colorScheme.onPrimary,
                      ),
                    ),
                    if (isPinned)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Symbols.push_pin,
                                size: 14,
                                color: colorScheme.onPrimaryContainer,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Pinjattu',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            // Start time + duration — explicit muted colour (A5).
            Center(
              child: Text(
                'Lähtö $startTime · $durationStr',
                style: TextStyle(color: semColors.onPrimaryMuted, fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
            // In-card CTA: solid surface for ≥ 13:1 against the gradient (A1).
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () =>
                    ref.read(tripProvider.notifier).stopTrip(context),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.surface,
                  foregroundColor: colorScheme.onPrimaryContainer,
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: const Text('Olen perillä'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addExpense(BuildContext context) async {
    final result =
        await showDialog<
          ({ExpenseType type, double amount, String? description})
        >(context: context, builder: (ctx) => const ExpenseDialog());
    if (result != null && widget.leg.id != null) {
      await DatabaseService.insertExpense(
        Expense(
          tripLegId: widget.leg.id,
          type: result.type,
          amount: result.amount,
          description: result.description,
          createdAt: DateTime.now().toIso8601String(),
        ),
      );
    }
  }
}

/// Animated pulse dot indicating a live trip.
class _LivePulse extends StatefulWidget {
  final bool paused;

  const _LivePulse({this.paused = false});

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
    );
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(_controller);
    if (!widget.paused) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _LivePulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.paused && _controller.isAnimating) {
      _controller.stop();
    } else if (!widget.paused && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
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
