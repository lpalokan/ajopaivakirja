import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../models/trip_leg.dart';
import '../providers/settings_provider.dart';
import '../services/database_service.dart';
import '../services/trip_calculator.dart';

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
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _hasUnsynced {
    for (final legs in _legsByDate.values) {
      if (legs.any((l) => !l.synced)) return true;
    }
    return false;
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

  Future<void> _syncAll() async {
    final settings = ref.read(settingsProvider);
    if (settings.sheetId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sheets-tunnusta ei ole määritetty')),
        );
      }
      return;
    }

    setState(() => _syncing = true);
    try {
      final sheets = ref.read(sheetsServiceProvider);
      final unsynced = await DatabaseService.getUnsyncedLegs();
      if (unsynced.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kaikki rivit on jo synkronoitu')),
          );
        }
        return;
      }
      await sheets.appendLegs(
        unsynced,
        sheetId: settings.sheetId,
        sheetTab: settings.sheetTab,
        onSynced: (legId) => DatabaseService.markLegSynced(legId),
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Synkronoitu ${unsynced.length} riviä')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Synkronointi epäonnistui: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _showEditDialog(TripLeg leg) async {
    final settings = ref.read(settingsProvider);
    final calc = TripCalculator(settings);

    final startOdoCtrl = TextEditingController(text: leg.startOdometer.toString());
    final endOdoCtrl = TextEditingController(text: leg.endOdometer?.toString() ?? '');
    final startLocCtrl = TextEditingController(text: leg.startLocation);
    final endLocCtrl = TextEditingController(text: leg.endLocation ?? '');
    final purposeCtrl = TextEditingController(text: leg.purpose ?? '');
    final driverCtrl = TextEditingController(text: leg.driver);

    var pickedStartTime = leg.startTime;
    var pickedEndTime = leg.endTime;
    var pickedType = leg.dailyAllowanceType;
    final timeFmt = DateFormat('HH:mm');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Muokkaa merkintää'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () async {
                    final t = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay.fromDateTime(pickedStartTime),
                    );
                    if (t != null) {
                      final d = pickedStartTime;
                      setDialogState(() {
                        pickedStartTime = DateTime(d.year, d.month, d.day, t.hour, t.minute);
                      });
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Alkamisaika',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.access_time),
                    ),
                    child: Text(timeFmt.format(pickedStartTime)),
                  ),
                ),
                const SizedBox(height: 12),
                if (leg.endTime != null)
                  InkWell(
                    onTap: () async {
                      final t = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay.fromDateTime(pickedEndTime!),
                      );
                      if (t != null) {
                        setDialogState(() {
                          pickedEndTime = DateTime(
                            pickedEndTime!.year, pickedEndTime!.month, pickedEndTime!.day,
                            t.hour, t.minute,
                          );
                        });
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Päättymisaika',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.access_time),
                      ),
                      child: Text(timeFmt.format(pickedEndTime!)),
                    ),
                  ),
                if (leg.endTime != null) const SizedBox(height: 12),
                TextField(
                  controller: startLocCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Lähtöpaikka',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: endLocCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Määränpää',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: startOdoCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Mittari alussa (km)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: endOdoCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Mittari lopussa (km)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: purposeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tarkoitus',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: driverCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Kuljettaja',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Päiväraha',
                    style: Theme.of(ctx).textTheme.titleSmall),
                RadioGroup<int?>(
                  groupValue: pickedType,
                  onChanged: (v) => setDialogState(() => pickedType = v),
                  child: Column(
                    children: [
                      RadioListTile<int?>(
                        value: null,
                        title: const Text('Automaattinen'),
                        dense: true,
                      ),
                      RadioListTile<int?>(
                        value: 0,
                        title: const Text('Ei päivärahaa'),
                        dense: true,
                      ),
                      RadioListTile<int?>(
                        value: 1,
                        title: const Text('Puolipäivä (>6h)'),
                        dense: true,
                      ),
                      RadioListTile<int?>(
                        value: 2,
                        title: const Text('Kokopäivä (>10h)'),
                        dense: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Peruuta'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Tallenna'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;

    final startOdo = int.tryParse(startOdoCtrl.text.trim()) ?? leg.startOdometer;
    final endOdoText = endOdoCtrl.text.trim();
    final endOdo = endOdoText.isNotEmpty ? int.tryParse(endOdoText) : leg.endOdometer;

    var updated = leg.copyWith(
      startTime: pickedStartTime,
      endTime: pickedEndTime,
      startLocation: startLocCtrl.text.trim(),
      endLocation: endLocCtrl.text.trim(),
      startOdometer: startOdo,
      endOdometer: endOdo,
      purpose: purposeCtrl.text.trim(),
      driver: driverCtrl.text.trim(),
      dailyAllowanceType: pickedType,
    );

    updated = calc.calculateLeg(updated);
    await DatabaseService.updateTripLeg(updated);

    // Recalculate daily allowance for the full day
    final dayLegs = await DatabaseService.getLegsForDate(leg.date);
    await calc.finalizeDay(dayLegs);

    await _load();
  }

  Future<void> _deleteLeg(TripLeg leg) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Poista merkintä'),
        content: Text(
          'Poistetaanko matka: ${leg.routeDescription ?? "${leg.startLocation} → ${leg.endLocation ?? "?"}"}?\n'
          '${leg.kmDriven.toStringAsFixed(1)} km · €${leg.totalAllowance.toStringAsFixed(2)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Peruuta'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Poista'),
          ),
        ],
      ),
    );

    if (confirm != true || leg.id == null) return;

    await DatabaseService.deleteTripLeg(leg.id!);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Merkintä poistettu')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historia'),
        actions: [
          if (_hasUnsynced)
            IconButton(
              onPressed: _syncing ? null : _syncAll,
              icon: _syncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload),
              tooltip: 'Synkronoi Sheetsiin',
            ),
        ],
      ),
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
                  PopupMenuButton<String>(
                    onSelected: (action) {
                      if (action == 'edit') {
                        _showEditDialog(leg);
                      } else if (action == 'delete') {
                        _deleteLeg(leg);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('Muokkaa')),
                      const PopupMenuItem(value: 'delete', child: Text('Poista')),
                    ],
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
