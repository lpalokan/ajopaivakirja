import 'dart:async';

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
/// Renders a gradient surface, an oversized primary metric, and a pulse
/// dot. An overflow menu houses _Kulu_ and _Peru matka_.
///
/// Primary metric per trip kind:
/// - **Route trip** — the route's predefined distance (e.g. "54.0 km").
///   Static for the duration of the trip; the actual km is computed from
///   the start/end odometer when the user enters arrival.
/// - **Ad-hoc trip** — elapsed time since start ("0 h 23 min"). km is not
///   shown while driving because, without a predefined estimate or a
///   reliable background-GPS counter, "0.0 km" would be misleading.
///
/// Why not GPS-based live km? `flutter_background_service` is pulled in
/// but never started, and Android suspends `whileInUse` location updates
/// once the app backgrounds — users typically lock the screen and drive.
/// A counter that ticks only when the app is in the foreground was both
/// unreliable and, for route trips, wrong: the predefined route length
/// was used as the baseline and live deltas were added on top, so the
/// number grew past the real route length. The GPS subscription was
/// dropped from `TripNotifier` accordingly.
///
/// The card calls [TripNotifier.stopTrip] / [TripNotifier.cancelTrip]
/// directly via Riverpod — it no longer receives callback props.
///
/// Accessibility (issue #46):
/// - A1: the "Olen perillä" CTA uses a solid surface, not a translucent
///   white-on-gradient — readable as a discrete shape ≥ 13:1 against the
///   gradient.
/// - A3: the whole card exposes a Semantics container so TalkBack
///   announces "Ajo käynnissä, …" with the primary metric.
/// - A5: muted text uses `SemanticColors.onPrimaryMuted` (an explicit
///   colour) rather than opacity, so its contrast is computable.
class ActiveTripCard extends ConsumerStatefulWidget {
  final TripLeg leg;

  const ActiveTripCard({super.key, required this.leg});

  @override
  ConsumerState<ActiveTripCard> createState() => _ActiveTripCardState();
}

class _ActiveTripCardState extends ConsumerState<ActiveTripCard> {
  /// Retained for a possible future re-introduction of a live counter.
  /// Currently unreachable — the freeze gesture (WCAG 2.2.2) was bound to
  /// a long-press on the primary metric, but the primary metric no longer
  /// moves, so the gesture binding is removed. Restoring the freeze just
  /// requires wrapping the primary-metric Column in a GestureDetector
  /// again with `onLongPress: _toggleFreeze` and
  /// `onTap: isPinned ? _toggleFreeze : null`.
  double? _frozenDistanceKm;

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    if (_isAdHoc) _startTicker();
  }

  @override
  void didUpdateWidget(covariant ActiveTripCard old) {
    super.didUpdateWidget(old);
    if (_isAdHoc) {
      _startTicker();
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  bool get _isAdHoc =>
      widget.leg.routeId == null && widget.leg.routeDescription == null;

  void _startTicker() {
    if (_ticker != null) return;
    // 30 s is fine: the unit displayed is whole minutes, so a faster tick
    // would just re-render the same string.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  // ignore: unused_element
  void _toggleFreeze() {
    setState(() {
      _frozenDistanceKm =
          _frozenDistanceKm == null ? widget.leg.kmDriven : null;
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

    final isAdHoc = _isAdHoc;
    final displayedKm = _frozenDistanceKm ?? widget.leg.kmDriven;
    final primaryStr =
        isAdHoc ? durationStr : '${displayedKm.toStringAsFixed(1)} km';
    final semanticsLabel = isAdHoc
        ? 'Ajo käynnissä, $durationStr'
        : 'Ajo käynnissä, ${displayedKm.toStringAsFixed(1)} kilometriä';
    final isPinned = _frozenDistanceKm != null;

    return Semantics(
      container: true,
      label: semanticsLabel,
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
            // Primary metric: km for route trips (static — see class doc),
            // elapsed time for ad-hoc trips.
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    primaryStr,
                    key: const ValueKey('active-trip-counter'),
                    style: numeralLarge.copyWith(color: colorScheme.onPrimary),
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
            const SizedBox(height: 4),
            // Start time (+ duration for route trips; duration is already
            // the primary metric for ad-hoc, so don't repeat it).
            Center(
              child: Text(
                isAdHoc ? 'Lähtö $startTime' : 'Lähtö $startTime · $durationStr',
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
