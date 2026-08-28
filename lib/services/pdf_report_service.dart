import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../models/trip_leg.dart';
import '../models/app_settings.dart';
import 'allowance_ledger.dart';
import 'trip_calculator.dart';

class PdfReportService {
  final AppSettings settings;

  PdfReportService(this.settings);

  /// Generate a Verohallinto-compliant PDF report for the given date range.
  Future<File> generate({
    required DateTime startDate,
    required DateTime endDate,
    required Map<String, List<TripLeg>> legsByDate,
    required AllowanceLedger ledger,
  }) async {
    // Embed a Unicode TTF so Finnish characters (ä ö å), the euro sign and
    // the en-dash render instead of the built-in font's missing-glyph box.
    final theme = pw.ThemeData.withFont(
      base: pw.Font.ttf(
        await rootBundle.load('assets/fonts/LiberationSans-Regular.ttf'),
      ),
      bold: pw.Font.ttf(
        await rootBundle.load('assets/fonts/LiberationSans-Bold.ttf'),
      ),
      italic: pw.Font.ttf(
        await rootBundle.load('assets/fonts/LiberationSans-Italic.ttf'),
      ),
      boldItalic: pw.Font.ttf(
        await rootBundle.load('assets/fonts/LiberationSans-BoldItalic.ttf'),
      ),
    );
    final doc = pw.Document(theme: theme);
    final dateFmt = DateFormat('d.M.yyyy', 'fi');
    final timeFmt = DateFormat('HH:mm', 'fi');
    final calculator = TripCalculator(settings);

    bool inRange(String date) {
      final dt = DateTime.parse(date);
      return !dt.isBefore(startDate) && !dt.isAfter(endDate);
    }

    // Only days with something to show. A day whose every leg is a draft is
    // not reported, so it must not pull its date into the report either.
    final legsForDate = <String, List<TripLeg>>{
      for (final entry in legsByDate.entries)
        if (inRange(entry.key))
          entry.key: entry.value.where((l) => l.isCompleted).toList(),
    }..removeWhere((_, legs) => legs.isEmpty);

    // A travel day in the middle of a long trip earns a päiväraha without any
    // driving. It has no legs, so nothing in legsByDate would ever mention
    // it — and it belongs in the report just as much as the days around it.
    final orphanDates = ledger
        .orphanDates(legsForDate.keys)
        .where(inRange)
        .toSet();

    final filteredDates = {...legsForDate.keys, ...orphanDates}.toList()
      ..sort();

    double grandTotalKm = 0;
    double grandTotalKmAllowance = 0;
    double grandTotalDailyAllowance = 0;

    final pages = <pw.Widget>[];

    // Header page
    pages.add(_buildHeader(dateFmt.format(startDate), dateFmt.format(endDate)));

    // Trip details
    for (final date in filteredDates) {
      final dailyAllowance = ledger.totalFor(date);

      if (orphanDates.contains(date)) {
        grandTotalDailyAllowance += dailyAllowance;
        pages.add(_buildAllowanceOnlySection(date, ledger, dateFmt));
        continue;
      }

      final legs = legsForDate[date]!;
      final summary = calculator.summarizeDay(
        legs,
        dailyAllowance: dailyAllowance,
      );

      grandTotalKm += summary.totalKm;
      grandTotalKmAllowance += summary.totalKmAllowance;
      grandTotalDailyAllowance += summary.totalDailyAllowance;

      pages.add(
        _buildDaySection(date, legs, summary, ledger, dateFmt, timeFmt),
      );
    }

    // Grand totals page
    pages.add(
      _buildGrandTotals(
        totalKm: grandTotalKm,
        totalKmAllowance: grandTotalKmAllowance,
        totalDailyAllowance: grandTotalDailyAllowance,
        grandTotal: grandTotalKmAllowance + grandTotalDailyAllowance,
      ),
    );

    doc.addPage(
      pw.MultiPage(
        // Landscape gives the trip table room for the odometer columns.
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => pages,
      ),
    );

    // Save to temp file
    final dir = Directory.systemTemp;
    final file = File(
      '${dir.path}/ajopaivakirja_raportti_'
      '${DateFormat('yyyy-MM-dd').format(startDate)}_'
      '${DateFormat('yyyy-MM-dd').format(endDate)}.pdf',
    );
    await file.writeAsBytes(await doc.save());
    return file;
  }

  pw.Widget _buildHeader(String startDateStr, String endDateStr) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Ajopäiväkirja – Matkalaskuraportti',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'Ajanjakso: $startDateStr – $endDateStr',
          style: const pw.TextStyle(fontSize: 12),
        ),
        pw.SizedBox(height: 4),
        if (settings.driverName.isNotEmpty)
          pw.Text(
            'Kuljettaja: ${settings.driverName}',
            style: const pw.TextStyle(fontSize: 12),
          ),
        pw.Text(
          'Kotiosoite: ${settings.homeLocation}',
          style: const pw.TextStyle(fontSize: 12),
        ),
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
      double grandTotal,
      bool estimated,
    })
    summary,
    AllowanceLedger ledger,
    DateFormat dateFmt,
    DateFormat timeFmt,
  ) {
    final displayDate = _formatDisplayDate(date, dateFmt);
    final hasDailyAllowance = summary.totalDailyAllowance > 0;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          displayDate,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        // Table header
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(0.8),
            1: const pw.FlexColumnWidth(0.8),
            2: const pw.FlexColumnWidth(1.2),
            3: const pw.FlexColumnWidth(1.2),
            4: const pw.FlexColumnWidth(0.9),
            5: const pw.FlexColumnWidth(0.9),
            6: const pw.FlexColumnWidth(0.7),
            7: const pw.FlexColumnWidth(1.2),
            8: const pw.FlexColumnWidth(1),
            9: const pw.FlexColumnWidth(1),
          },
          children: [
            pw.TableRow(
              children: [
                _tableHeader('Alkoi'),
                _tableHeader('Päättyi'),
                _tableHeader('Lähtö'),
                _tableHeader('Määränpää'),
                _tableHeader('Mittari alussa'),
                _tableHeader('Mittari lopussa'),
                _tableHeader('Km'),
                _tableHeader('Tarkoitus'),
                _tableHeader('Km-korv. €'),
                _tableHeader('Päiväraha €'),
              ],
            ),
            ...legs.map(
              (leg) => pw.TableRow(
                children: [
                  _tableCell(timeFmt.format(leg.startTime)),
                  _tableCell(
                    leg.endTime != null ? timeFmt.format(leg.endTime!) : '',
                  ),
                  _tableCell(leg.startLocation),
                  _tableCell(leg.endLocation ?? ''),
                  _tableCell(leg.startOdometer.toString()),
                  _tableCell(leg.endOdometer?.toString() ?? ''),
                  _tableCell(leg.kmDriven.toStringAsFixed(1)),
                  _tableCell(leg.purpose ?? ''),
                  _tableCell(leg.kmAllowance.toStringAsFixed(2)),
                  _tableCell(_allowanceCell(ledger.forLeg(leg, legs))),
                ],
              ),
            ),
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
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
          ],
        ),
        if (hasDailyAllowance)
          pw.Text(
            _dailyAllowanceText(date, legs, ledger),
            style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic),
          ),
        pw.SizedBox(height: 12),
        pw.Divider(),
        pw.SizedBox(height: 8),
      ],
    );
  }

  static String _allowanceCell(double amount) =>
      amount > 0 ? amount.toStringAsFixed(2) : '';

  /// The line under a day's table explaining what it was paid, and — when the
  /// driver overrode it — that a person decided so rather than the clock.
  String _dailyAllowanceText(
    String date,
    List<TripLeg> legs,
    AllowanceLedger ledger,
  ) {
    final described = ledger.describe(date);
    if (described == null) return 'Päiväraha: Ei oikeutta (alle 6h)';
    final manual = legs.any(
      (l) => l.date == date && l.dailyAllowanceType != null,
    );
    return manual
        ? 'Päiväraha: $described (manuaalinen)'
        : 'Päiväraha: $described';
  }

  /// A travel day with no driving at all. It is still a day away from home,
  /// so it is still paid — and a report that skipped it would under-report
  /// the trip.
  pw.Widget _buildAllowanceOnlySection(
    String date,
    AllowanceLedger ledger,
    DateFormat dateFmt,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          _formatDisplayDate(date, dateFmt),
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Ei ajoja — matkapäivä työmatkan keskellä',
          style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Päiväraha: ${ledger.totalFor(date).toStringAsFixed(2)} € '
          '(${ledger.describe(date)})',
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 12),
        pw.Divider(),
        pw.SizedBox(height: 8),
      ],
    );
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
        pw.Text(
          'Yhteenveto',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Divider(),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Kilometrit yhteensä:',
              style: const pw.TextStyle(fontSize: 12),
            ),
            pw.Text(
              '${totalKm.toStringAsFixed(1)} km',
              style: const pw.TextStyle(fontSize: 12),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Kilometrikorvaukset:',
              style: const pw.TextStyle(fontSize: 12),
            ),
            pw.Text(
              '${totalKmAllowance.toStringAsFixed(2)} €',
              style: const pw.TextStyle(fontSize: 12),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Päivärahat:', style: const pw.TextStyle(fontSize: 12)),
            pw.Text(
              '${totalDailyAllowance.toStringAsFixed(2)} €',
              style: const pw.TextStyle(fontSize: 12),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Divider(),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'YHTEENSÄ:',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              '${grandTotal.toStringAsFixed(2)} €',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _tableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      ),
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
