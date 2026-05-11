import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/trip_leg.dart';
import '../services/database_service.dart';

class TripHistoryScreen extends ConsumerStatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  ConsumerState<TripHistoryScreen> createState() =>
      _TripHistoryScreenState();
}

class _TripHistoryScreenState extends ConsumerState<TripHistoryScreen> {
  List<String> _dates = [];
  Map<String, List<TripLeg>> _legsByDate = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final dates = await DatabaseService.getDistinctDates();
    final legsByDate = <String, List<TripLeg>>{};
    for (final date in dates) {
      legsByDate[date] = await DatabaseService.getLegsForDate(date);
    }
    if (mounted) {
      setState(() {
        _dates = dates;
        _legsByDate = legsByDate;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historia')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _dates.isEmpty
              ? const Center(child: Text('Ei ajohistoriaa'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _dates.length,
                  itemBuilder: (context, index) {
                    final date = _dates[index];
                    final legs = _legsByDate[date]!;
                    return _buildDateGroup(date, legs);
                  },
                ),
    );
  }

  Widget _buildDateGroup(String date, List<TripLeg> legs) {
    final totalKm = legs.fold<double>(0, (s, l) => s + l.kmDriven);
    final totalAllowance =
        legs.fold<double>(0, (s, l) => s + l.kmAllowance + l.dailyAllowance);
    final displayDate = _formatDisplayDate(date);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(displayDate,
                    style: Theme.of(context).textTheme.titleSmall),
                Text(
                  '${totalKm.toStringAsFixed(1)} km · €${totalAllowance.toStringAsFixed(2)}',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          for (final leg in legs)
            ListTile(
              dense: true,
              title: Text(
                  leg.routeDescription ?? '${leg.startLocation} → ${leg.endLocation ?? "-"}'),
              subtitle: Text(
                '${_formatTime(leg.startTime)}–${leg.endTime != null ? _formatTime(leg.endTime!) : "..."} · '
                '${leg.kmDriven.toStringAsFixed(1)} km',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('€${leg.totalAllowance.toStringAsFixed(2)}'),
                  if (!leg.synced)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(Icons.cloud_off,
                          size: 16,
                          color: Theme.of(context).colorScheme.outline),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatDisplayDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      final fmt = DateFormat('EEEE d.M.yyyy', 'fi');
      return fmt.format(dt);
    } catch (_) {
      return isoDate;
    }
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
