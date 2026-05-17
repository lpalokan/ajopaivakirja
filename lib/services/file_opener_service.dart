import 'package:open_filex/open_filex.dart';

/// Opens a file with an external app via the platform's "view" intent
/// (Android `ACTION_VIEW`), so the user can pick an app of their choice —
/// e.g. Google Sheets / Excel for CSV, or a PDF viewer for PDF. This is
/// distinct from sharing (`ACTION_SEND`), which most viewer apps don't
/// register for and therefore don't appear in the share sheet.
///
/// Wrapped in an injectable service so the integration harness can fake
/// the native call, like the other external-world services.
class FileOpenerService {
  /// Opens the file at [path]. Returns null on success, or a Finnish
  /// user-facing error message when the file could not be opened.
  Future<String?> open(String path) async {
    final result = await OpenFilex.open(path);
    switch (result.type) {
      case ResultType.done:
        return null;
      case ResultType.noAppToOpen:
        return 'Tiedostotyypille ei löytynyt sovellusta';
      case ResultType.permissionDenied:
        return 'Tiedoston avaaminen estettiin';
      case ResultType.fileNotFound:
        return 'Tiedostoa ei löytynyt';
      case ResultType.error:
        return 'Tiedoston avaaminen epäonnistui';
    }
  }
}
