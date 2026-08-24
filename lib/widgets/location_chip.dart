import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import '../providers/position_provider.dart';
import '../services/database_service.dart';
import '../models/location_zone.dart';
import 'location_autocomplete.dart';

/// Source of the location label shown in the chip.
enum LocationChipSource { zone, picked, fallback, searching }

/// A chip that shows where the driver is right now and doubles as the trip's
/// start-location field.
///
/// The position itself comes from [currentPositionProvider], not from this
/// widget: the chip used to resolve GPS once in `initState` and then show
/// that first answer forever, which is exactly the staleness this is fixed
/// to avoid. Here it only renders the shared position and lets the user
/// override or remember it.
///
/// - Tapping opens the [LocationAutocomplete] dialog to override.
/// - Long-pressing saves the resolved position as a new [LocationZone].
class LocationChip extends ConsumerStatefulWidget {
  final ValueChanged<String> onChanged;

  /// Pre-populated fallback label (e.g. last used endLocation), shown while
  /// the position is unknown.
  final String? fallbackLabel;

  const LocationChip({super.key, required this.onChanged, this.fallbackLabel});

  @override
  ConsumerState<LocationChip> createState() => LocationChipState();
}

class LocationChipState extends ConsumerState<LocationChip> {
  /// A location the user typed or picked by hand. Wins over GPS until the
  /// trip starts — the driver knows better than the geofence.
  String? _override;

  /// Last GPS-derived name handed to [LocationChip.onChanged]. Kept so a
  /// rebuild doesn't re-notify the parent with a name it already has.
  String? _notifiedName;

  @override
  void initState() {
    super.initState();
    // Ask for a fresh fix as soon as the chip appears. Cheap when one is
    // already in flight (the notifier collapses concurrent refreshes).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(currentPositionProvider.notifier).refresh();
    });
  }

  /// What the chip is currently offering as the start location.
  ({String label, LocationChipSource source}) _resolveLabel(
    CurrentPositionState position,
  ) {
    final override = _override;
    if (override != null && override.isNotEmpty) {
      return (label: override, source: LocationChipSource.picked);
    }

    final place = position.placeName;
    if (place != null && place.isNotEmpty) {
      return (label: place, source: LocationChipSource.zone);
    }

    final fallback = widget.fallbackLabel;
    if (fallback != null && fallback.isNotEmpty) {
      return (label: fallback, source: LocationChipSource.fallback);
    }

    if (position.status == PositionStatus.searching) {
      return (label: 'Etsitään...', source: LocationChipSource.searching);
    }
    return (label: 'Ei sijaintia', source: LocationChipSource.fallback);
  }

  /// Why the chip is showing a fallback rather than where we are. Without
  /// this, "no location permission" and "GPS hasn't answered yet" look
  /// identical — the user has no way to tell that the chip is never going
  /// to catch up on its own.
  String _suffixFor(CurrentPositionState position) =>
      position.status == PositionStatus.noPermission
      ? '  (ei sijaintilupaa)'
      : '  (edellinen)';

  IconData _iconFor(LocationChipSource source) => switch (source) {
    LocationChipSource.searching => Symbols.location_searching,
    LocationChipSource.zone => Symbols.my_location,
    LocationChipSource.picked => Symbols.near_me,
    LocationChipSource.fallback => Symbols.place,
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final position = ref.watch(currentPositionProvider);
    final resolved = _resolveLabel(position);
    final searching = resolved.source == LocationChipSource.searching;

    // Tell the parent about a GPS-resolved place as soon as we have one, so
    // "Aloita ajo" starts from where the driver actually is. A manual pick
    // has already been reported by the picker itself and must not be
    // overwritten here.
    final place = position.placeName;
    if (_override == null && place != null && place != _notifiedName) {
      _notifiedName = place;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onChanged(place);
      });
    }

    // NOTE: no Tooltip wrapper here — its long-press recognizer would win
    // the gesture arena against _saveAsZone, silently killing "long-press to
    // remember this place".
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
                _iconFor(resolved.source),
                size: 18,
                color: resolved.source == LocationChipSource.zone
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                resolved.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (resolved.source == LocationChipSource.fallback)
              Text(
                _suffixFor(position),
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
          ],
        ),
        onPressed: searching
            ? null
            : () => _showLocationPicker(context, resolved.label),
      ),
    );
  }

  /// Opens a dialog that lets the user override the auto-detected location
  /// by typing or picking from previously-used locations.
  Future<void> _showLocationPicker(BuildContext context, String current) async {
    final suggestions = await DatabaseService.getUniqueLocations();
    final ctrl = TextEditingController(text: current);

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
      setState(() => _override = result);
      widget.onChanged(result);
    }
  }

  /// Long-press: remember the spot we are standing on under the chip's
  /// current label, so GPS can name it (and surface its routes) next time.
  Future<void> _saveAsZone() async {
    final position = ref.read(currentPositionProvider);
    final fix = position.position;
    final current = _resolveLabel(position).label;
    if (fix == null || current.isEmpty) return;

    final nameCtrl = TextEditingController(text: current);
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
          latitude: fix.latitude,
          longitude: fix.longitude,
          radiusMeters: radius,
          createdAt: DateTime.now().toIso8601String(),
        ),
      );
      // The chip is named after a zone match, so it only picks up the new
      // zone once the fix is re-matched against the table.
      if (mounted) await ref.read(currentPositionProvider.notifier).rematch();
    }
  }
}
