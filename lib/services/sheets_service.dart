import 'package:http/http.dart' as http;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/auth_io.dart';
import '../models/trip_leg.dart';
import 'log_service.dart';

class SheetsService {
  final GoogleSignIn _googleSignIn;
  sheets.SheetsApi? _sheetsApi;
  http.Client? _authClient;

  static const _headerRow = [
    'Päivämäärä',
    'Alkamisaika',
    'Alussa',
    'Päättymisaika',
    'Lopussa',
    'Alkamispaikka',
    'Päättymispaikka',
    'Ajoreitti',
    'Matkan pituus',
    'Tarkoitus',
    'Käyttäjä',
    'Km-korvaus €',
    'Päiväraha €',
    'Yhteensä €',
    'Tuntia',
    'Työaika',
    'ID',
  ];

  SheetsService()
      : _googleSignIn = GoogleSignIn(
          scopes: [
            sheets.SheetsApi.spreadsheetsScope,
            drive.DriveApi.driveReadonlyScope,
          ],
        );

  bool isConfigured(String sheetId) => sheetId.isNotEmpty;

  Future<bool> get isSignedIn => _googleSignIn.isSignedIn();

  Future<void> signIn() async {
    try {
      LogService().info('Google Sign-In: silent attempt...');
      final silentAccount = await _googleSignIn.signInSilently();
      if (silentAccount != null) {
        await _buildApiClient(silentAccount);
        LogService().info('Google Sign-In: restored session');
        return;
      }
    } catch (e) {
      LogService().warn('Google Sign-In: silent attempt failed ($e)');
    }

    try {
      LogService().info('Google Sign-In: starting interactive...');
      final account = await _googleSignIn.signIn();
      if (account == null) {
        LogService().warn('Google Sign-In: cancelled by user');
        throw Exception('Kirjautuminen peruttu');
      }
      LogService().info('Google Sign-In: got account (${account.email})');
      await _buildApiClient(account);
      LogService().info('Google Sign-In: success');
    } catch (e, st) {
      LogService().error('Google Sign-In failed', e, st);
      rethrow;
    }
  }

  Future<void> _buildApiClient(GoogleSignInAccount account) async {
    final authHeaders = await account.authHeaders;
    LogService().info('Google Sign-In: got auth headers');

    final credentials = AccessCredentials(
      AccessToken(
        'Bearer',
        authHeaders['Authorization']!.replaceFirst('Bearer ', ''),
        DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
      null,
      [
        sheets.SheetsApi.spreadsheetsScope,
        drive.DriveApi.driveReadonlyScope,
      ],
    );

    final client = GoogleAuthClient(credentials, http.Client());
    _authClient = client;
    _sheetsApi = sheets.SheetsApi(client);
  }

  Future<void> _ensureApiClient() async {
    if (_sheetsApi != null) return;
    if (!await _googleSignIn.isSignedIn()) return;

    try {
      final account = await _googleSignIn.signInSilently();
      if (account != null) {
        await _buildApiClient(account);
        LogService().info('Google Sign-In: auto-reconnected');
      }
    } catch (e) {
      LogService().warn('Google Sign-In: auto-reconnect failed ($e)');
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _authClient?.close();
    _authClient = null;
    _sheetsApi = null;
  }

  Future<List<drive.File>> listSpreadsheets() async {
    await _ensureApiClient();
    if (_authClient == null) {
      throw Exception('Ei kirjauduttu Googleen. Kirjaudu asetuksista.');
    }

    final driveApi = drive.DriveApi(_authClient!);
    final fileList = await driveApi.files.list(
      q: "mimeType='application/vnd.google-apps.spreadsheet'",
      pageSize: 50,
      orderBy: 'modifiedTime desc',
      $fields: 'files(id,name,modifiedTime)',
    );
    return fileList.files ?? [];
  }

  Future<void> _ensureSheet(String sheetId, String tabName) async {
    try {
      LogService().info('Sheets: checking tab "$tabName"...');
      final spreadsheet = await _sheetsApi!.spreadsheets.get(sheetId, includeGridData: false);
      final exists = spreadsheet.sheets?.any((s) => s.properties?.title == tabName) ?? false;

      if (exists) {
        LogService().info('Sheets: tab "$tabName" found');
        return;
      }

      LogService().info('Sheets: tab "$tabName" not found, creating...');
      final requests = [
        sheets.Request(
          addSheet: sheets.AddSheetRequest(
            properties: sheets.SheetProperties(title: tabName),
          ),
        ),
      ];

      await _sheetsApi!.spreadsheets.batchUpdate(
        sheets.BatchUpdateSpreadsheetRequest(requests: requests),
        sheetId,
      );
      LogService().info('Sheets: tab "$tabName" created');

      // Write header row
      final headerRange = "'$tabName'!A1:Q1";
      await _sheetsApi!.spreadsheets.values.update(
        sheets.ValueRange()..range = headerRange..values = [_headerRow],
        sheetId,
        headerRange,
        valueInputOption: 'USER_ENTERED',
      );
      LogService().info('Sheets: header row written to "$tabName"');
    } catch (e) {
      LogService().error('Sheets: _ensureSheet failed', e);
      throw Exception('Välilehden "$tabName" luonti epäonnistui: $e');
    }
  }

  Future<Map<String, int>> _buildIdRowMap(String sheetId, String sheetTab) async {
    final map = <String, int>{};
    try {
      final response = await _sheetsApi!.spreadsheets.values.get(
        sheetId,
        "'$sheetTab'!Q:Q",
      );
      final rows = response.values;
      if (rows != null) {
        for (var i = 0; i < rows.length; i++) {
          final row = rows[i];
          if (row.isNotEmpty) {
            final id = row[0]?.toString() ?? '';
            if (id.isNotEmpty) {
              map[id] = i + 1;
            }
          }
        }
      }
      LogService().info('Sheets: ID map built (${map.length} rows)');
    } catch (e) {
      LogService().warn('Sheets: could not read ID column ($e), will append all');
    }
    return map;
  }

  Future<void> appendLeg(TripLeg leg, {
    required String sheetId,
    required String sheetTab,
    Map<String, int>? idToRow,
  }) async {
    await _ensureApiClient();
    if (_sheetsApi == null) {
      throw Exception('Ei kirjauduttu Googleen. Kirjaudu asetuksista.');
    }
    if (sheetId.isEmpty) {
      throw Exception('Google Sheets -tunnusta ei ole määritetty asetuksissa.');
    }

    await _ensureSheet(sheetId, sheetTab);

    final row = _legToRow(leg);
    final legId = leg.id?.toString() ?? '';

    if (idToRow != null && legId.isNotEmpty && idToRow.containsKey(legId)) {
      final rowNum = idToRow[legId]!;
      final range = "'$sheetTab'!A${rowNum}:Q${rowNum}";
      await _sheetsApi!.spreadsheets.values.update(
        sheets.ValueRange()..range = range..values = [row],
        sheetId,
        range,
        valueInputOption: 'USER_ENTERED',
      );
      LogService().info('Sheets: updated row $rowNum for leg $legId');
    } else {
      final range = "'$sheetTab'!A1:Q1";
      await _sheetsApi!.spreadsheets.values.append(
        sheets.ValueRange()..range = range..values = [row],
        sheetId,
        range,
        valueInputOption: 'USER_ENTERED',
        insertDataOption: 'INSERT_ROWS',
      );
      LogService().info('Sheets: appended leg $legId');
    }
  }

  Future<int> appendLegs(
    List<TripLeg> legs, {
    required String sheetId,
    required String sheetTab,
    Future<void> Function(int legId)? onSynced,
  }) async {
    await _ensureApiClient();
    if (_sheetsApi == null) throw Exception('Ei kirjauduttu Googleen.');
    await _ensureSheet(sheetId, sheetTab);

    final idToRow = await _buildIdRowMap(sheetId, sheetTab);
    var synced = 0;

    for (final leg in legs) {
      try {
        await appendLeg(leg, sheetId: sheetId, sheetTab: sheetTab, idToRow: idToRow);
        await onSynced?.call(leg.id!);
        synced++;
      } catch (e) {
        LogService().error('Sheets: append/update failed for leg ${leg.id}', e);
        throw Exception('Synkronointi epäonnistui: $e');
      }
    }

    LogService().info('Sheets: sync complete ($synced legs)');
    return synced;
  }

  List<Object?> _legToRow(TripLeg leg) {
    final startTime = leg.startTime;
    final endTime = leg.endTime;
    final dateFormat = _formatDate(startTime);
    final startTimeStr = _formatTime(startTime);
    final endTimeStr = endTime != null ? _formatTime(endTime) : '';

    return [
      dateFormat,
      startTimeStr,
      leg.startOdometer,
      endTimeStr,
      leg.endOdometer ?? '',
      leg.startLocation,
      leg.endLocation ?? '',
      leg.routeDescription ?? '',
      leg.kmDriven,
      leg.purpose ?? '',
      leg.driver,
      leg.kmAllowance,
      leg.dailyAllowance,
      leg.totalAllowance,
      leg.legDurationHours,
      leg.workingTimeHours,
      leg.id?.toString() ?? '',
    ];
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}.${dt.month}.${dt.year}';
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void dispose() {
    _authClient?.close();
    _authClient = null;
    _sheetsApi = null;
  }
}

class GoogleAuthClient extends http.BaseClient {
  final AccessCredentials _credentials;
  final http.Client _inner;

  GoogleAuthClient(this._credentials, this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers['Authorization'] =
        'Bearer ${_credentials.accessToken.data}';
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
