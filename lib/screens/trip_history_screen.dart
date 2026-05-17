import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../main.dart';
import '../models/trip_leg.dart';
import '../providers/settings_provider.dart';
import '../services/database_service.dart';
import '../services/trip_calculator.dart';
import '../services/pdf_report_service.dart';
import '../services/csv_export_service.dart';
import '../models/expense.dart';

class TripHistoryScreen extends ConsumerStatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  ConsumerState<TripHistoryScreen> createState() =>
      _TripHistoryScreenState();
}

class _TripHistoryScreenState extends ConsumerState<TripHistoryScreen> {
  List<String> _dates = [];
  Map<String, List<TripLeg>> _legsByDate = {};
  Map<int, List<Expense>> _expensesByLegId = {};
  bool _loading = true;
  bool _syncing = false;
  Map<int, double> _kmRates = {};

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
    if (!mounted) return;
    setState(() => _loading = true);
    _kmRates = await DatabaseService.getAllKmRates();
    final dates = await DatabaseService.getDistinctDates();
    final legsByDate = <String, List<TripLeg>>{};
    for (final date in dates) {
      legsByDate[date] = await DatabaseService.getLegsForDate(date);
    }
    // Load expenses for all legs
    final allLegIds = legsByDate.values.expand((l) => l).map((l) => l.id).whereType<int>().toList();
    _expensesByLegId = await DatabaseService.getExpensesForLegs(allLegIds);
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

    if (!_hasUnsynced) {
      final deletedIds = await DatabaseService.getDeletedLegIds();
      if (deletedIds.isEmpty) {
        if (!mounted) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Ei muutoksia'),
            content: const Text('Ei muutoksia synkronoitavana. Haluatko silti päivittää?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Peruuta')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Synkronoi')),
            ],
          ),
        );
        if (confirm != true) return;
      }
    }

    setState(() => _syncing = true);
    try {
      final sheets = ref.read(sheetsServiceProvider);
      final unsynced = await DatabaseService.getUnsyncedLegs();
      final deletedIds = await DatabaseService.getDeletedLegIds();
      if (unsynced.isEmpty && deletedIds.isEmpty) {
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
        deletedLegIds: deletedIds,
        onSynced: (legId) => DatabaseService.markLegSynced(legId),
      );
      if (deletedIds.isNotEmpty) {
        await DatabaseService.clearDeletedLegIds(deletedIds);
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Synkronoitu: ${unsynced.length} riviä${deletedIds.isNotEmpty ? ', poistettu ${deletedIds.length}' : ''}')),
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
    final calc = TripCalculator(settings, kmRates: _kmRates);

    final startOdoCtrl = TextEditingController(text: leg.startOdometer.toString());
    final endOdoCtrl = TextEditingController(text: leg.endOdometer?.toString() ?? '');
    final startLocCtrl = TextEditingController(text: leg.startLocation);
    final endLocCtrl = TextEditingController(text: leg.endLocation ?? '');
    final purposeCtrl = TextEditingController(text: leg.purpose ?? '');
    final driverCtrl = TextEditingController(text: leg.driver);

    var pickedStartTime = leg.startTime;
    var pickedEndTime = leg.endTime;
    var pickedType = leg.dailyAllowanceType;
    var pickedDate = DateTime.parse(leg.date);
    final timeFmt = DateFormat('HH:mm');
    final dateFmt = DateFormat('d.M.yyyy');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: null,
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Muokkaa merkintää', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: pickedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (d != null) setDialogState(() => pickedDate = d);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Päivämäärä',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    child: Text(dateFmt.format(pickedDate)),
                  ),
                ),
                const SizedBox(height: 12),
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
      date: DateFormat('yyyy-MM-dd').format(pickedDate),
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
    if (updated.id != null) {
      await DatabaseService.markLegUnsynced(updated.id!);
    }

    // Recalculate daily allowance for both old and new dates
    final oldDateLegs = await DatabaseService.getLegsForDate(leg.date);
    if (oldDateLegs.isNotEmpty) {
      await calc.finalizeDay(oldDateLegs);
      for (final l in oldDateLegs) {
        if (l.id != null) await DatabaseService.markLegUnsynced(l.id!);
      }
    }
    final newDate = DateFormat('yyyy-MM-dd').format(pickedDate);
    if (newDate != leg.date) {
      final newDateLegs = await DatabaseService.getLegsForDate(newDate);
      if (newDateLegs.isNotEmpty) {
        await calc.finalizeDay(newDateLegs);
        for (final l in newDateLegs) {
          if (l.id != null) await DatabaseService.markLegUnsynced(l.id!);
        }
      }
    }

    await _load();
  }

  Future<bool> _deleteLeg(TripLeg leg) async {
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

    if (confirm != true || leg.id == null) return false;

    await DatabaseService.deleteTripLeg(leg.id!);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Merkintä poistettu')),
      );
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historia'),
        actions: [
          IconButton(
            onPressed: _legsByDate.isNotEmpty ? _exportCsv : null,
            icon: const Icon(Icons.table_chart),
            tooltip: 'Vie CSV',
          ),
          IconButton(
            onPressed: _legsByDate.isNotEmpty ? _exportPdf : null,
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Vie PDF-raportti',
          ),
          IconButton(
            onPressed: _syncing ? null : _syncAll,
            icon: _syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.cloud_upload,
                    color: _hasUnsynced
                        ? null
                        : Theme.of(context).colorScheme.outline),
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

  Future<void> _exportCsv() async {
    try {
      // Collect all legs
      final allLegs = <TripLeg>[];
      for (final date in _dates) {
        allLegs.addAll(_legsByDate[date]!);
      }

      final file = await CsvExportService.generate(
        legs: allLegs,
        expensesByLegId: _expensesByLegId,
      );

      if (mounted) {
        await _shareOrSave(file, 'Ajopäiväkirja CSV-vienti');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CSV:n luonti epäonnistui: $e')),
        );
      }
    }
  }

  /// Let the user choose between sharing/opening the file with another app
  /// or saving it to the device's Downloads folder.
  Future<void> _shareOrSave(File file, String shareText) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Tallenna Lataukset-kansioon'),
              onTap: () => Navigator.pop(ctx, 'save'),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Jaa tai avaa sovelluksessa'),
              onTap: () => Navigator.pop(ctx, 'share'),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Peruuta'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );

    if (choice == 'share') {
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        text: shareText,
      ));
    } else if (choice == 'save') {
      await _saveToDownloads(file);
    }
  }

  Future<void> _saveToDownloads(File file) async {
    final name = file.path.split('/').last;
    File? saved;
    String? error;
    try {
      var target = Directory('/storage/emulated/0/Download');
      if (!await target.exists()) {
        final ext = await getExternalStorageDirectory();
        final fallback =
            ext?.path ?? (await getApplicationDocumentsDirectory()).path;
        target = Directory(fallback);
      }
      if (!await target.exists()) {
        await target.create(recursive: true);
      }
      saved = await file.copy('${target.path}/$name');
    } catch (e) {
      error = '$e';
      try {
        final docs = await getApplicationDocumentsDirectory();
        saved = await file.copy('${docs.path}/$name');
        error = null;
      } catch (e2) {
        error = '$e2';
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved != null
            ? 'Tallennettu: ${saved.path}'
            : 'Tallennus epäonnistui: $error'),
      ),
    );
  }

  Future<void> _exportPdf() async {
    // Show date range picker
    DateTime startDate = DateTime.now().subtract(const Duration(days: 365));
    DateTime endDate = DateTime.now();

    // Find earliest and latest dates
    if (_dates.isNotEmpty) {
      try {
        final firstDate = DateTime.parse(_dates.last);
        final lastDate = DateTime.parse(_dates.first);
        startDate = firstDate;
        endDate = lastDate;
      } catch (_) {}
    }

    if (!mounted) return;

    final range = await showDialog<({DateTime start, DateTime end})?>(
      context: context,
      builder: (ctx) => _PdfDateRangeDialog(
        initialStart: startDate,
        initialEnd: endDate,
      ),
    );

    if (range == null || !mounted) return;

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final settings = ref.read(settingsProvider);
      final service = PdfReportService(settings);

      final file = await service.generate(
        startDate: range.start,
        endDate: range.end,
        legsByDate: _legsByDate,
      );

      if (mounted) {
        Navigator.of(context).pop(); // close loading
        await _shareOrSave(file, 'Ajopäiväkirja PDF-raportti');
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF:n luonti epäonnistui: $e')),
        );
      }
    }
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
          for (final leg in legs) ...[
            Dismissible(
              key: Key('leg_${leg.id}'),
              direction: DismissDirection.endToStart,
              confirmDismiss: (_) async {
                return await _deleteLeg(leg);
              },
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                color: Theme.of(context).colorScheme.error,
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              child: ListTile(
                dense: true,
                onTap: () => _showEditDialog(leg),
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
                    const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
            ),
            // Show expenses for this leg
            if (leg.id != null)
              ..._buildExpenseRows(leg.id!),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildExpenseRows(int legId) {
    final expenses = _expensesByLegId[legId] ?? [];
    return expenses.map((exp) {
      return Padding(
        padding: const EdgeInsets.only(left: 56, right: 16, bottom: 2),
        child: Row(
          children: [
            Icon(Icons.receipt_long, size: 14, color: Theme.of(context).colorScheme.outline),
            const SizedBox(width: 6),
            Text(
              exp.type.displayName,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (exp.description != null && exp.description!.isNotEmpty) ...[
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  exp.description!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const Spacer(),
            Text(
              '${exp.amount.toStringAsFixed(2)} €',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            SizedBox(
              width: 24,
              height: 24,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 14,
                icon: Icon(Icons.delete_outline,
                    color: Theme.of(context).colorScheme.outline),
                onPressed: () => _deleteExpense(exp),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Future<void> _deleteExpense(Expense exp) async {
    if (exp.id == null) return;
    await DatabaseService.deleteExpense(exp.id!);
    await _load();
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

class _PdfDateRangeDialog extends StatefulWidget {
  final DateTime initialStart;
  final DateTime initialEnd;

  const _PdfDateRangeDialog({
    required this.initialStart,
    required this.initialEnd,
  });

  @override
  State<_PdfDateRangeDialog> createState() => _PdfDateRangeDialogState();
}

class _PdfDateRangeDialogState extends State<_PdfDateRangeDialog> {
  late DateTime _start;
  late DateTime _end;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d.M.yyyy', 'fi');
    return AlertDialog(
      title: const Text('Vie PDF-raportti'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Valitse ajanjakso raportille:'),
          const SizedBox(height: 16),
          InkWell(
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _start,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (d != null) setState(() => _start = d);
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Aloituspäivä',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.calendar_today),
              ),
              child: Text(dateFmt.format(_start)),
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _end,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (d != null) setState(() => _end = d);
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Päättymispäivä',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.calendar_today),
              ),
              child: Text(dateFmt.format(_end)),
            ),
          ),
          if (_end.isBefore(_start))
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Päättymispäivä on ennen aloituspäivää',
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Peruuta'),
        ),
        FilledButton(
          onPressed: _end.isBefore(_start)
              ? null
              : () => Navigator.pop(
                    context,
                    (start: _start, end: _end),
                  ),
          child: const Text('Luo PDF'),
        ),
      ],
    );
  }
}
