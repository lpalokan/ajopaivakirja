import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../models/trip_leg.dart';
import '../models/expense.dart';

class CsvExportService {
  /// UTF-8 BOM. Excel on Windows and many Android spreadsheet apps assume the
  /// legacy locale codepage for BOM-less CSV, mangling Scandinavian characters;
  /// Google Sheets rejects such files as corrupted. The BOM forces UTF-8.
  static const String _bom = '\uFEFF';

  /// RFC 4180 record separator. Maximises importer compatibility.
  static const String _crlf = '\r\n';

  /// Generate CSV content string for the given legs and optional expenses.
  static String generateContent(
    List<TripLeg> legs, {
    Map<int, List<Expense>>? expensesByLegId,
  }) {
    final buf = StringBuffer();
    buf.write(_bom);

    // Header
    buf.write(_header());
    buf.write(_crlf);

    // Rows, sorted by date then leg order
    final sorted = List<TripLeg>.from(legs)
      ..sort((a, b) {
        final dateCmp = a.date.compareTo(b.date);
        if (dateCmp != 0) return dateCmp;
        return a.legOrder.compareTo(b.legOrder);
      });

    for (final leg in sorted) {
      if (!leg.isCompleted) continue; // skip drafts
      buf.write(_row(leg));
      buf.write(_crlf);

      // Append expense rows for this leg
      final legExpenses = expensesByLegId?[leg.id] ?? [];
      for (final exp in legExpenses) {
        buf.write(_expenseRow(leg, exp));
        buf.write(_crlf);
      }
    }

    return buf.toString();
  }

  /// Generate a CSV file for the given legs and optional expenses.
  /// Returns the file path.
  static Future<File> generate({
    required List<TripLeg> legs,
    Map<int, List<Expense>>? expensesByLegId,
    String? fileName,
  }) async {
    final content = generateContent(legs, expensesByLegId: expensesByLegId);

    // Save to documents directory
    final dir = await getApplicationDocumentsDirectory();
    final name = fileName ?? 'ajopaivakirja_export_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
    final file = File('${dir.path}/$name');
    await file.writeAsString(content);
    return file;
  }

  static String _header() {
    return [
      'Päivämäärä',
      'Järjestys',
      'Lähtöaika',
      'Päättymisaika',
      'Lähtöpaikka',
      'Määränpää',
      'Reitti',
      'Mittari alussa',
      'Mittari lopussa',
      'Ajetut km',
      'Tarkoitus',
      'Kuljettaja',
      'Km-korvaus (€)',
      'Päiväraha (€)',
      'Päivärahatyyppi',
      'Kotiinpaluu',
      'Tuntia',
      'Työaika',
      'Tyyppi (kulu/matka)',
      'Kulutyyppi',
      'Kulun summa (€)',
      'Kulun kuvaus',
    ].join(',');
  }

  static String _row(TripLeg leg) {
    final timeFmt = DateFormat('HH:mm');
    final dailyTypeStr = switch (leg.dailyAllowanceType) {
      0 => 'Ei päivärahaa',
      1 => 'Puolipäivä (>6h)',
      2 => 'Kokopäivä (>10h)',
      _ => 'Automaattinen',
    };

    return _csvLine([
      leg.date,
      leg.legOrder.toString(),
      timeFmt.format(leg.startTime),
      leg.endTime != null ? timeFmt.format(leg.endTime!) : '',
      _escape(leg.startLocation),
      _escape(leg.endLocation ?? ''),
      _escape(leg.routeDescription ?? ''),
      leg.startOdometer.toString(),
      leg.endOdometer?.toString() ?? '',
      leg.kmDriven.toStringAsFixed(1),
      _escape(leg.purpose ?? ''),
      _escape(leg.driver),
      leg.kmAllowance.toStringAsFixed(2),
      leg.dailyAllowance.toStringAsFixed(2),
      dailyTypeStr,
      leg.isReturnHome ? 'Kyllä' : 'Ei',
      leg.legDurationHours.toStringAsFixed(2),
      leg.workingTimeHours.toStringAsFixed(2),
      'Matka',
      '',
      '',
      '',
    ]);
  }

  static String _expenseRow(TripLeg leg, Expense exp) {
    final typeStr = exp.type.displayName;
    return _csvLine([
      leg.date,
      leg.legOrder.toString(),
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      'Kulu',
      typeStr,
      exp.amount.toStringAsFixed(2),
      _escape(exp.description ?? ''),
    ]);
  }

  static String _csvLine(List<String> values) {
    return values.join(',');
  }

  static String _escape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
