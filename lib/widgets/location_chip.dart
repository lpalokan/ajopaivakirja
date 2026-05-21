import 'dart:async';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import '../services/location_service.dart';
import '../services/database_service.dart';
import '../models/location_zone.dart';
import 'location_autocomplete.dart';

/// Source of the location label shown in the chip.
enum LocationChipSource { zone, geocoded, fallback, searching }

/// A chip that auto-resolves the user's GPS location and displays a label.
///
/// - Tapping opens the [LocationAutocomplete] dialog to override.
/// - Long-pressing saves the resolved position as a new [LocationZone].
class LocationChip extends StatefulWidget {
  final LocationService locationService;
  final ValueChanged<String> onChanged;

  /// Pre-populated fallback label (e.g. last used endLocation).
  final String? fallbackLabel;

  const LocationChip({
    super.key,
    required this.locationService,
    required this.onChanged,
    this.fallbackLabel,
  });

  @override
  State<LocationChip> createState() => _LocationChipState();
}

class _LocationChipState extends State<LocationChip> {
  LocationChipSource _source = LocationChipSource.searching;
  String _label = '';
  String? _resolvedLat;
  String? _resolvedLon;

  @override
  void initState() {
    super.initState();
    // Show fallback immediately while resolving
    if (widget.fallbackLabel != null && widget.fallbackLabel!.isNotEmpty) {
      _label = widget.fallbackLabel!;
      _source = LocationChipSource.fallback;
    } else {
      _label = 'Etsitään...';
    }
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final hasPerm = await widget.locationService.hasPermissionGranted();
      if (!hasPerm) {
        _setFallbackOrEmpty();
        return;
      }

      final pos = await widget.locationService.getCurrentPosition().timeout(
        const Duration(seconds: 3),
      );
      if (pos == null) {
        _setFallbackOrEmpty();
        return;
      }

      _resolvedLat = pos.latitude.toString();
      _resolvedLon = pos.longitude.toString();

      // Check saved zones
      final zones = await DatabaseService.getAllLocationZones();
      for (final zone in zones) {
        final dist = LocationService.haversineDistance(
          pos.latitude,
          pos.longitude,
          zone.latitude,
          zone.longitude,
        );
        if (dist <= zone.radiusMeters) {
          if (!mounted) return;
          setState(() {
            _label = zone.name;
            _source = LocationChipSource.zone;
          });
          widget.onChanged(zone.name);
          return;
        }
      }

      // Reverse geocoding fallback
      final name = await widget.locationService.getLocationName(pos);
      if (!mounted) return;
      if (name != null && name.isNotEmpty) {
        setState(() {
          _label = name;
          _source = LocationChipSource.geocoded;
        });
        widget.onChanged(name);
      } else {
        _setFallbackOrEmpty();
      }
    } catch (_) {
      _setFallbackOrEmpty();
    }
  }

  void _setFallbackOrEmpty() {
    if (!mounted) return;
    if (_label.isNotEmpty && _source == LocationChipSource.fallback) return;
    setState(() {
      if (widget.fallbackLabel != null && widget.fallbackLabel!.isNotEmpty) {
        _label = widget.fallbackLabel!;
        _source = LocationChipSource.fallback;
      } else {
        _label = 'Ei sijaintia';
        _source = LocationChipSource.fallback;
      }
    });
  }

  String get label => _label;

  IconData get _icon {
    return switch (_source) {
      LocationChipSource.searching => Symbols.location_searching,
      LocationChipSource.zone => Symbols.my_location,
      LocationChipSource.geocoded => Symbols.near_me,
      LocationChipSource.fallback => Symbols.place,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final searching = _source == LocationChipSource.searching;

    return GestureDetector(
      onLongPress: _saveAsZone,
      child: InputChip(
        isEnabled: !searching,
        avatar: searching
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                _icon,
                size: 18,
                color: _source == LocationChipSource.zone
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(_label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (_source == LocationChipSource.fallback)
              const Text(
                '  (edellinen)',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
          ],
        ),
        onPressed: searching ? null : () => _showLocationPicker(context),
      ),
    );
  }

  /// Opens a dialog that lets the user override the auto-detected location
  /// by typing or picking from previously-used locations.
  Future<void> _showLocationPicker(BuildContext context) async {
    final suggestions = await DatabaseService.getUniqueLocations();
    final ctrl = TextEditingController(text: _label);

    if (!context.mounted) return;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Muuta sijainti'),
        content: SizedBox(
          width: double.maxFinite,
          child: LocationAutocomplete(
            controller: ctrl,
            label: 'Sijainti',
            suggestions: suggestions,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Peruuta'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Käytä'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && mounted) {
      setState(() => _label = result);
      widget.onChanged(result);
    }
  }

  Future<void> _saveAsZone() async {
    if (_label.isEmpty || _resolvedLat == null || _resolvedLon == null) return;

    final nameCtrl = TextEditingController(text: _label);
    final radiusCtrl = TextEditingController(text: '100');

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tallenna alueeksi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nimi'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: radiusCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Säde (metriä)',
                suffixText: 'm',
              ),
            ),
          ],
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
    );

    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      final radius = double.tryParse(radiusCtrl.text.trim()) ?? 100;
      await DatabaseService.insertLocationZone(
        LocationZone(
          name: nameCtrl.text.trim(),
          latitude: double.parse(_resolvedLat!),
          longitude: double.parse(_resolvedLon!),
          radiusMeters: radius,
          createdAt: DateTime.now().toIso8601String(),
        ),
      );
    }
  }
}
