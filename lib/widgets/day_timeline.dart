import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/trip_leg.dart';
import '../main.dart';

/// A vertical timeline showing today's completed trips and inline drafts.
///
/// Left rail: filled markers for completed stops, hollow for active/draft
/// endpoints. Dashed rail segments for drafts.
class DayTimeline extends StatelessWidget {
  final List<TripLeg> legs;
  final Map<int, double>? kmRates;
  final ValueChanged<TripLeg> onTapLeg;

  const DayTimeline({
    super.key,
    required this.legs,
    this.kmRates,
    required this.onTapLeg,
  });

  @override
  Widget build(BuildContext context) {
    if (legs.isEmpty) return const SizedBox.shrink();

    final dailyKm = legs.fold<double>(0, (s, l) => s + l.kmDriven);
    final dailyAllowance = legs.fold<double>(
      0,
      (s, l) => s + l.kmAllowance + l.dailyAllowance,
    );

    final timeFmt = DateFormat('HH:mm');
    final tripCountLabel = legs.length == 1 ? 'matka' : 'matkaa';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'Tänään · ${legs.length} $tripCountLabel',
                    style: Theme.of(context).textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${dailyKm.toStringAsFixed(1)} km · €${dailyAllowance.toStringAsFixed(2)}',
                  style: Theme.of(context)
                      .extension<NumeralTypography>()!
                      .small
                      .copyWith(color: Theme.of(context).colorScheme.tertiary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < legs.length; i++)
              _buildTimelineRow(context, legs[i], i, legs.length, timeFmt),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineRow(
    BuildContext context,
    TripLeg leg,
    int index,
    int total,
    DateFormat timeFmt,
  ) {
    final isDraft = leg.isDraft;
    final colorScheme = Theme.of(context).colorScheme;
    final markerColor = isDraft ? Colors.amber.shade700 : colorScheme.primary;
    final railStyle = isDraft ? _dashedLine() : _solidLine();

    return InkWell(
      onTap: () => onTapLeg(leg),
      borderRadius: BorderRadius.circular(8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left rail column
            SizedBox(
              width: 32,
              child: Column(
                children: [
                  // Top rail segment
                  if (index > 0) Expanded(child: _railSegment(railStyle)),
                  // Marker
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: markerColor, width: 2),
                      color: isDraft ? Colors.transparent : markerColor,
                    ),
                  ),
                  // Bottom rail segment (only if not last)
                  if (index < total - 1)
                    Expanded(child: _railSegment(railStyle)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Right body
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  leg.routeDescription ??
                                      '${leg.startLocation} → ${leg.endLocation ?? '...'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                              if (isDraft) ...[
                                const SizedBox(width: 6),
                                Text(
                                  'Täydennä',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${timeFmt.format(leg.startTime)}–${leg.endTime != null ? timeFmt.format(leg.endTime!) : '...'} · '
                            '${leg.kmDriven.toStringAsFixed(1)} km',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${leg.kmDriven.toStringAsFixed(1)} km',
                          style: Theme.of(context)
                              .extension<NumeralTypography>()!
                              .small
                              .copyWith(color: colorScheme.onSurface),
                        ),
                        Text(
                          '€${leg.totalAllowance.toStringAsFixed(2)}',
                          style: Theme.of(context)
                              .extension<NumeralTypography>()!
                              .inline_
                              .copyWith(color: colorScheme.tertiary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _railSegment(Paint paint) {
    return CustomPaint(painter: _RailPainter(paint));
  }

  Paint _solidLine() {
    return Paint()
      ..color = Colors.blue
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
  }

  Paint _dashedLine() {
    return Paint()
      ..color = Colors.amber.shade700
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
  }
}

class _RailPainter extends CustomPainter {
  final Paint linePaint;
  _RailPainter(this.linePaint);

  @override
  void paint(Canvas canvas, Size size) {
    // Draw a vertical dotted line in the center
    final path = Path();
    const dashHeight = 4.0;
    const gapHeight = 4.0;
    var y = 0.0;
    while (y < size.height) {
      path.moveTo(size.width / 2, y);
      path.lineTo(size.width / 2, y + dashHeight);
      y += dashHeight + gapHeight;
    }
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
