import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../main.dart';
import '../providers/settings_provider.dart';
import '../services/log_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _homeController = TextEditingController();
  final _kmRateController = TextEditingController();
  final _allowance6hController = TextEditingController();
  final _allowance10hController = TextEditingController();
  final _sheetIdController = TextEditingController();
  final _sheetTabController = TextEditingController();
  final _driverController = TextEditingController();

  bool _saving = false;
  bool _signingIn = false;
  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _homeController.text = settings.homeLocation;
    _kmRateController.text = settings.kmRate.toString();
    _allowance6hController.text = settings.allowance6h.toString();
    _allowance10hController.text = settings.allowance10h.toString();
    _sheetIdController.text = settings.sheetId;
    _sheetTabController.text = settings.sheetTab;
    _driverController.text = settings.driverName;
    _checkSignIn();
  }

  Future<void> _checkSignIn() async {
    final sheets = ref.read(sheetsServiceProvider);
    _signedIn = await sheets.isSignedIn;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _homeController.dispose();
    _kmRateController.dispose();
    _allowance6hController.dispose();
    _allowance10hController.dispose();
    _sheetIdController.dispose();
    _sheetTabController.dispose();
    _driverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Asetukset')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionHeader('Perustiedot'),
            TextFormField(
              controller: _homeController,
              decoration: const InputDecoration(
                labelText: 'Kotiosoite',
                hintText: 'Esim. Koti',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _driverController,
              decoration: const InputDecoration(
                labelText: 'Kuljettajan nimi',
                hintText: 'Oma nimi',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            _sectionHeader('Korvaukset'),
            TextFormField(
              controller: _kmRateController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Km-korvaus (€/km)',
                suffixText: '€/km',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _allowance6hController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Päiväraha (yli 6h)',
                suffixText: '€',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _allowance10hController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Päiväraha (yli 10h)',
                suffixText: '€',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            _sectionHeader('Google Sheets'),
            _buildSheetsAuthButton(),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _sheetIdController,
                    decoration: const InputDecoration(
                      labelText: 'Sheets-tiedoston ID',
                      hintText: 'URL:stä löytyvä tunniste',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 56,
                  child: OutlinedButton(
                    onPressed: _signedIn ? _showFilePicker : null,
                    child: const Icon(Icons.folder_open),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _sheetTabController,
              decoration: const InputDecoration(
                labelText: 'Välilehden nimi',
                hintText: 'Esim. Taulukko1',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _sectionHeader('Vianmääritys'),
            SwitchListTile(
              title: const Text('Virheloki'),
              subtitle: const Text('Tallentaa lokitiedoston puhelimeen'),
              value: ref.watch(settingsProvider).debugLogging,
              onChanged: (v) async {
                await ref.read(settingsProvider.notifier).update({
                  'debug_logging': v ? '1' : '0',
                });
                LogService().setEnabled(v);
                if (v) {
                  await LogService().init(enabled: true);
                }
                setState(() {});
              },
            ),
            if (ref.watch(settingsProvider).debugLogging)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _shareLogs,
                        icon: const Icon(Icons.share),
                        label: const Text('Jaa loki'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _copyLogsToDownloads,
                        icon: const Icon(Icons.download),
                        label: const Text('Tallenna tiedot'),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(_saving ? 'Tallennetaan...' : 'Tallenna'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  Widget _buildSheetsAuthButton() {
    if (_signedIn) {
      return Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 20),
          const SizedBox(width: 8),
          const Text('Kirjautunut Googleen'),
          const Spacer(),
          TextButton(
            onPressed: _signOut,
            child: const Text('Kirjaudu ulos'),
          ),
        ],
      );
    }
    return OutlinedButton.icon(
      onPressed: _signingIn ? null : _signIn,
      icon: _signingIn
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.login),
      label: Text(_signingIn ? 'Kirjaudutaan...' : 'Kirjaudu Googleen'),
    );
  }

  Future<void> _signIn() async {
    setState(() => _signingIn = true);
    try {
      final sheets = ref.read(sheetsServiceProvider);
      await sheets.signIn();
      _signedIn = true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kirjautuminen epäonnistui: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _signOut() async {
    final sheets = ref.read(sheetsServiceProvider);
    await sheets.signOut();
    _signedIn = false;
    if (mounted) setState(() {});
  }

  Future<void> _showFilePicker() async {
    final sheets = ref.read(sheetsServiceProvider);

    await showDialog(
      context: context,
      builder: (ctx) => _FilePickerDialog(sheets: sheets, onSelect: (id) {
        _sheetIdController.text = id;
        Navigator.pop(ctx);
      }),
    );
  }

  Future<void> _copyLogsToDownloads() async {
    final logService = LogService();
    final content = await logService.readLogs();
    final srcPath = logService.logPath;
    if (srcPath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lokitiedostoa ei löydy')),
        );
      }
      return;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final destPath = '${dir.path}/kilometrikorvaus.log';
      final dest = File(destPath);
      await dest.writeAsString(content);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tallennettu: $destPath')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tallennus epäonnistui: $e')),
        );
      }
    }
  }

  Future<void> _shareLogs() async {
    final logService = LogService();
    final content = await logService.readLogs();
    final path = logService.logPath;
    if (path == null) return;

    // Write to a shareable temp file
    final tempPath = '${(await getApplicationDocumentsDirectory()).path}/kilometrikorvaus_export.log';
    final file = File(tempPath);
    await file.writeAsString(content);

    await SharePlus.instance.share(ShareParams(
      files: [XFile(tempPath)],
      text: 'Kilometrikorvaus debug log',
    ));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final kmRateStr = _kmRateController.text.replaceAll(',', '.');
      final a6hStr = _allowance6hController.text.replaceAll(',', '.');
      final a10hStr = _allowance10hController.text.replaceAll(',', '.');

      await ref.read(settingsProvider.notifier).update({
        'home_location': _homeController.text.trim(),
        'km_rate': kmRateStr,
        'allowance_6h': a6hStr,
        'allowance_10h': a10hStr,
        'sheet_id': _sheetIdController.text.trim(),
        'sheet_tab': _sheetTabController.text.trim(),
        'driver_name': _driverController.text.trim(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Asetukset tallennettu')),
        );
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _FilePickerDialog extends StatefulWidget {
  final dynamic sheets;
  final void Function(String id) onSelect;

  const _FilePickerDialog({required this.sheets, required this.onSelect});

  @override
  State<_FilePickerDialog> createState() => _FilePickerDialogState();
}

class _FilePickerDialogState extends State<_FilePickerDialog> {
  List<dynamic>? _files;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await widget.sheets.listSpreadsheets();
      if (mounted) {
        setState(() {
          _files = result;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Valitse tiedosto'),
      content: SizedBox(
        width: double.maxFinite,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
                ? Text(_error!, style: const TextStyle(color: Colors.red))
                : _files == null || _files!.isEmpty
                    ? const Text('Ei tiedostoja')
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _files!.length,
                        itemBuilder: (_, i) {
                          final f = _files![i];
                          final name = f.name ?? 'Nimetön';
                          return ListTile(
                            leading: const Icon(Icons.table_chart),
                            title: Text(name),
                            onTap: () => widget.onSelect(f.id ?? ''),
                          );
                        },
                      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Peruuta'),
        ),
      ],
    );
  }
}
