import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../models/trip_leg.dart';
import '../models/expense.dart';
import 'allowance_ledger.dart';

class CsvExportService {
  /// UTF-8 BOM. Excel on Windows and many Android spreadsheet apps assume the
  /// legacy locale codepage for BOM-less CSV, mangling Scandinavian characters;
  /// Google Sheets rejects such files as corrupted. The BOM forces UTF-8.
  static const String _bom = '\uFEFF';

  /// RFC 4180 record separator. Maximises importer compatibility.
  static const String _crlf = '\r\n';

  /// Generate CSV content string for the given legs and optional expenses.
  ///
  /// [ledger] is what the export pays in päivärahaa. It is required rather
  /// than optional because the alternative — reading the figure mirrored onto
  /// each leg — cannot see a travel day that has no legs, and quietly
  /// under-reports the middle day of a long trip.
  static String generateContent(
    List<TripLeg> legs, {
    required AllowanceLedger ledger,
    Map<int, List<Expense>>? expensesByLegId,
  }) {
    final buf = StringBuffer();
    buf.write(_bom);

    buf.write(_header());
    buf.write(_crlf);

    // Rows, sorted by date then leg order
    final sorted = List<TripLeg>.from(legs)
      ..sort((a, b) {
        final dateCmp = a.date.compareTo(b.date);
        if (dateCmp != 0) return dateCmp;
        return a.legOrder.compareTo(b.legOrder);
      });

    // Drafts never reach the file, so they must not carry a day's päiväraha
    // either: the ledger is laid over the legs that actually get exported.
    final exported = sorted.where((l) => l.isCompleted).toList();
    final byDate = <String, List<TripLeg>>{};
    for (final leg in exported) {
      byDate.putIfAbsent(leg.date, () => []).add(leg);
    }

    // A travel day with no legs of its own still earned its päiväraha. It
    // gets a row in date order rather than being dropped.
    final orphanDates = ledger.orphanDates(byDate.keys).toList();
    var nextOrphan = 0;
    void writeOrphansBefore(String? date) {
      while (nextOrphan < orphanDates.length &&
          (date == null || orphanDates[nextOrphan].compareTo(date) < 0)) {
        final orphan = orphanDates[nextOrphan++];
        buf.write(_allowanceRow(orphan, ledger));
        buf.write(_crlf);
      }
    }

    for (final leg in exported) {
      writeOrphansBefore(leg.date);
      buf.write(_row(leg, ledger, byDate[leg.date]!));
      buf.write(_crlf);

      // Append expense rows for this leg
      final legExpenses = expensesByLegId?[leg.id] ?? [];
      for (final exp in legExpenses) {
        buf.write(_expenseRow(leg, exp));
        buf.write(_crlf);
      }
    }
    writeOrphansBefore(null);

    return buf.toString();
  }

  /// Generate a CSV file for the given legs and optional expenses.
  /// Returns the file path.
  static Future<File> generate({
    required List<TripLeg> legs,
    required AllowanceLedger ledger,
    Map<int, List<Expense>>? expensesByLegId,
    String? fileName,
  }) async {
    final content = generateContent(
      legs,
      ledger: ledger,
      expensesByLegId: expensesByLegId,
    );

    // Save to documents directory
    final dir = await getApplicationDocumentsDirectory();
    final name =
        fileName ??
        'ajopaivakirja_export_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
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

  static String _dailyTypeLabel(int? type) => switch (type) {
    0 => 'Ei päivärahaa',
    1 => 'Puolipäivä (>6h)',
    2 => 'Kokopäivä (>10h)',
    _ => 'Automaattinen',
  };

  static String _row(
    TripLeg leg,
    AllowanceLedger ledger,
    List<TripLeg> legsOnDate,
  ) {
    final timeFmt = DateFormat('HH:mm');
    final dailyAllowance = ledger.forLeg(leg, legsOnDate);
    // The type describes the money, so it is printed on the row that carries
    // it. Naming a type on a 0,00 row would double-count it by eye.
    final dailyTypeStr = dailyAllowance > 0
        ? _dailyTypeLabel(ledger.typeFor(leg.date))
        : '';

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
      dailyAllowance.toStringAsFixed(2),
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

  /// A travel day that earned a päiväraha without any driving — the middle
  /// day of a trip that stayed away overnight. It has no leg, so it gets a
  /// row of its own, in the same shape as an expense row.
  static String _allowanceRow(String date, AllowanceLedger ledger) {
    return _csvLine([
      date,
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      _escape(ledger.describe(date) ?? ''),
      '',
      '',
      ledger.totalFor(date).toStringAsFixed(2),
      _dailyTypeLabel(ledger.typeFor(date)),
      '',
      '',
      '',
      'Päiväraha',
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
