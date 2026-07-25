import '../models/trip_leg.dart';
import 'database_service.dart';
import 'log_service.dart';
import 'sheets_service.dart';

/// What a single sync run should send, once the export spreadsheet has been
/// resolved.
class SheetsSyncPlan {
  final SheetsTarget target;
  final List<TripLeg> legs;
  final List<int> deletedLegIds;

  const SheetsSyncPlan({
    required this.target,
    required this.legs,
    required this.deletedLegIds,
  });
}

/// Resolve the export spreadsheet and work out what has to go into it.
///
/// Shared by the automatic sync (day close, [TripNotifier]) and the manual one
/// (the History screen's sync button) so the two can't drift apart. Under the
/// `drive.file` scope the app can only touch a spreadsheet it created itself,
/// so [SheetsService.ensureSpreadsheet] may hand back a brand-new, empty file
/// — either on first use or because the stored id predates the scope change.
/// When that happens the caller's list of legs is not enough: the whole
/// history has to be written again, and any queued row deletions refer to rows
/// that no longer exist.
Future<SheetsSyncPlan> prepareSheetsSync({
  required SheetsService sheets,
  required String sheetId,
  required String sheetTab,
  required List<TripLeg> legs,
  required Future<void> Function(String sheetId) persistSheetId,
}) async {
  final target = await sheets.ensureSpreadsheet(
    sheetId: sheetId,
    tabName: sheetTab,
  );

  if (target.id != sheetId) {
    await persistSheetId(target.id);
  }

  if (!target.created) {
    return SheetsSyncPlan(
      target: target,
      legs: legs,
      deletedLegIds: await DatabaseService.getDeletedLegIds(),
    );
  }

  final pendingDeletes = await DatabaseService.getDeletedLegIds();
  if (pendingDeletes.isNotEmpty) {
    await DatabaseService.clearDeletedLegIds(pendingDeletes);
  }
  await DatabaseService.markAllLegsUnsynced();
  final all = await DatabaseService.getUnsyncedLegs();
  LogService().info(
    'Sheets: new spreadsheet ${target.id} — re-syncing ${all.length} legs',
  );

  return SheetsSyncPlan(target: target, legs: all, deletedLegIds: const []);
}
