import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../models/trip_leg.dart';
import '../models/app_settings.dart';
import 'trip_calculator.dart';

class PdfReportService {
  final AppSettings settings;

  PdfReportService(this.settings);

  /// Generate a Verohallinto-compliant PDF report for the given date range.
  Future<File> generate({
    required DateTime startDate,
    required DateTime endDate,
    required Map<String, List<TripLeg>> legsByDate,
  }) async {
    final doc = pw.Document();
    final dateFmt = DateFormat('d.M.yyyy', 'fi');
    final timeFmt = DateFormat('HH:mm', 'fi');
    final calculator = TripCalculator(settings);

    // Group and sort dates
    final sortedDates = legsByDate.keys.toList()..sort();

    // Filter by date range
    final filteredDates = sortedDates.where((d) {
      final dt = DateTime.parse(d);
      return !dt.isBefore(startDate) && !dt.isAfter(endDate);
    }).toList();

    double grandTotalKm = 0;
    double grandTotalKmAllowance = 0;
    double grandTotalDailyAllowance = 0;

    final pages = <pw.Widget>[];

    // Header page
    pages.add(_buildHeader(dateFmt.format(startDate), dateFmt.format(endDate)));

    // Trip details
    for (final date in filteredDates) {
      final legs = legsByDate[date]!;
      final summary = calculator.summarizeDay(legs);

      grandTotalKm += summary.totalKm;
      grandTotalKmAllowance += summary.totalKmAllowance;
      grandTotalDailyAllowance += summary.totalDailyAllowance;

      pages.add(_buildDaySection(date, legs, summary, dateFmt, timeFmt));
    }

    // Grand totals page
    pages.add(_buildGrandTotals(
      totalKm: grandTotalKm,
      totalKmAllowance: grandTotalKmAllowance,
      totalDailyAllowance: grandTotalDailyAllowance,
      grandTotal: grandTotalKmAllowance + grandTotalDailyAllowance,
    ));

    // Signature page
    pages.add(_buildSignaturePage());

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (context) => pages,
    ));

    // Save to temp file
    final dir = Directory.systemTemp;
    final file = File('${dir.path}/ajopaivakirja_raportti_'
        '${DateFormat('yyyy-MM-dd').format(startDate)}_'
        '${DateFormat('yyyy-MM-dd').format(endDate)}.pdf');
    await file.writeAsBytes(await doc.save());
    return file;
  }

  pw.Widget _buildHeader(String startDateStr, String endDateStr) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Ajopäiväkirja – Matkalaskuraportti',
            style: pw.TextStyle(
                fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Text('Ajanjakso: $startDateStr – $endDateStr',
            style: const pw.TextStyle(fontSize: 12)),
        pw.SizedBox(height: 4),
        if (settings.driverName.isNotEmpty)
          pw.Text('Kuljettaja: ${settings.driverName}',
              style: const pw.TextStyle(fontSize: 12)),
        pw.Text('Kotiosoite: ${settings.homeLocation}',
            style: const pw.TextStyle(fontSize: 12)),
        pw.SizedBox(height: 8),
        pw.Divider(),
        pw.SizedBox(height: 8),
      ],
    );
  }

  pw.Widget _buildDaySection(
    String date,
    List<TripLeg> legs,
    ({
      double totalKm,
      double totalKmAllowance,
      double totalDailyAllowance,
      double grandTotal
    }) summary,
    DateFormat dateFmt,
    DateFormat timeFmt,
  ) {
    final displayDate = _formatDisplayDate(date, dateFmt);
    final hasDailyAllowance = legs.any((l) => l.dailyAllowance > 0);
    final dailyAllowanceLeg = legs.cast<TripLeg?>().lastWhere(
        (l) => l!.dailyAllowance > 0, orElse: () => null);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(displayDate,
            style: pw.TextStyle(
                fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        // Table header
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(0.8),
            1: const pw.FlexColumnWidth(0.8),
            2: const pw.FlexColumnWidth(0.8),
            3: const pw.FlexColumnWidth(1.2),
            4: const pw.FlexColumnWidth(0.8),
            5: const pw.FlexColumnWidth(1.2),
            6: const pw.FlexColumnWidth(1),
            7: const pw.FlexColumnWidth(1),
          },
          children: [
            pw.TableRow(
              children: [
                _tableHeader('Alkoi'),
                _tableHeader('Päättyi'),
                _tableHeader('Lähtö'),
                _tableHeader('Määränpää'),
                _tableHeader('Km'),
                _tableHeader('Tarkoitus'),
                _tableHeader('Km-korv. €'),
                _tableHeader('Päiväraha €'),
              ],
            ),
            ...legs.map((leg) => pw.TableRow(
                  children: [
                    _tableCell(timeFmt.format(leg.startTime)),
                    _tableCell(
                        leg.endTime != null ? timeFmt.format(leg.endTime!) : ''),
                    _tableCell(leg.startLocation),
                    _tableCell(leg.endLocation ?? ''),
                    _tableCell(leg.kmDriven.toStringAsFixed(1)),
                    _tableCell(leg.purpose ?? ''),
                    _tableCell(leg.kmAllowance.toStringAsFixed(2)),
                    _tableCell(leg.dailyAllowance > 0
                        ? leg.dailyAllowance.toStringAsFixed(2)
                        : ''),
                  ],
                )),
          ],
        ),
        pw.SizedBox(height: 4),
        // Day summary
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Yht. ${summary.totalKm.toStringAsFixed(1)} km',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.Text(
              'Km-korvaus: ${summary.totalKmAllowance.toStringAsFixed(2)} €',
              style: const pw.TextStyle(fontSize: 10),
            ),
            if (hasDailyAllowance)
              pw.Text(
                'Päiväraha: ${summary.totalDailyAllowance.toStringAsFixed(2)} €',
                style: pw.TextStyle(
                    fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
          ],
        ),
        if (dailyAllowanceLeg != null)
          pw.Text(
            _dailyAllowanceText(dailyAllowanceLeg),
            style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic),
          ),
        pw.SizedBox(height: 12),
        pw.Divider(),
        pw.SizedBox(height: 8),
      ],
    );
  }

  String _dailyAllowanceText(TripLeg leg) {
    if (leg.dailyAllowanceType == 0) return 'Päiväraha: Ei päivärahaa (manuaalinen)';
    if (leg.dailyAllowanceType == 1) return 'Päiväraha: Puolipäivä (>6h, manuaalinen)';
    if (leg.dailyAllowanceType == 2) return 'Päiväraha: Kokopäivä (>10h, manuaalinen)';
    if (leg.dailyAllowance > 0) {
      final hours = leg.legDurationHours;
      if (hours > 10) return 'Päiväraha: Kokopäivä (>10h, ${hours.toStringAsFixed(1)}h)';
      return 'Päiväraha: Puolipäivä (>6h, ${hours.toStringAsFixed(1)}h)';
    }
    return 'Päiväraha: Ei oikeutta (alle 6h)';
  }

  pw.Widget _buildGrandTotals({
    required double totalKm,
    required double totalKmAllowance,
    required double totalDailyAllowance,
    required double grandTotal,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 16),
        pw.Text('Yhteenveto',
            style: pw.TextStyle(
                fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Divider(),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Kilometrit yhteensä:',
                style: const pw.TextStyle(fontSize: 12)),
            pw.Text('${totalKm.toStringAsFixed(1)} km',
                style: const pw.TextStyle(fontSize: 12)),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Kilometrikorvaukset:',
                style: const pw.TextStyle(fontSize: 12)),
            pw.Text('${totalKmAllowance.toStringAsFixed(2)} €',
                style: const pw.TextStyle(fontSize: 12)),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Päivärahat:',
                style: const pw.TextStyle(fontSize: 12)),
            pw.Text('${totalDailyAllowance.toStringAsFixed(2)} €',
                style: const pw.TextStyle(fontSize: 12)),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Divider(),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('YHTEENSÄ:',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Text('${grandTotal.toStringAsFixed(2)} €',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'Huom: kilometrikorvaukset ovat verovapaita Verohallinnon vahvistaman '
          'enimmäismäärän mukaisesti. Päivärahat eivät ole veronalaista tuloa.',
          style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic),
        ),
      ],
    );
  }

  pw.Widget _buildSignaturePage() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 40),
        pw.Text('Vakuutus',
            style: pw.TextStyle(
                fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 12),
        pw.Text(
          'Vakuutan, että yllä mainitut matkat on tehty ilmoitettuna aikana '
          'ja ilmoitetulla ajoneuvolla, ja että kilometrikorvaukset on laskettu '
          'Verohallinnon kulloinkin vahvistaman enimmäismäärän mukaisesti.',
          style: const pw.TextStyle(fontSize: 11),
        ),
        pw.SizedBox(height: 40),
        pw.Row(
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Paikka ja aika: ___________________________',
                    style: const pw.TextStyle(fontSize: 11)),
              ],
            ),
            pw.SizedBox(width: 40),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Allekirjoitus: ___________________________',
                    style: const pw.TextStyle(fontSize: 11)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.Row(
          children: [
            pw.Text('Nimen selvennys: ${settings.driverName}',
                style: const pw.TextStyle(fontSize: 11)),
          ],
        ),
        pw.SizedBox(height: 40),
        pw.Divider(),
        pw.SizedBox(height: 8),
        pw.Text(
          'Raportti luotu: ${DateFormat('d.M.yyyy HH:mm', 'fi').format(DateTime.now())} '
          '• Ajopäiväkirja v1.0.0',
          style: pw.TextStyle(fontSize: 8, color: PdfColors.grey),
        ),
      ],
    );
  }

  pw.Widget _tableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(text,
          style: pw.TextStyle(
              fontSize: 8, fontWeight: pw.FontWeight.bold)),
    );
  }

  pw.Widget _tableCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 8)),
    );
  }

  String _formatDisplayDate(String isoDate, DateFormat dateFmt) {
    try {
      final dt = DateTime.parse(isoDate);
      final fmt = DateFormat('EEEE d.M.yyyy', 'fi');
      return fmt.format(dt);
    } catch (_) {
      return isoDate;
    }
  }
}
