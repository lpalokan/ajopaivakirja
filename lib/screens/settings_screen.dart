import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';

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
            TextFormField(
              controller: _sheetIdController,
              decoration: const InputDecoration(
                labelText: 'Sheets-tiedoston ID',
                hintText: 'URL:stä löytyvä tunniste',
                border: OutlineInputBorder(),
              ),
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
