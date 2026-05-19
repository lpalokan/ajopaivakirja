import 'dart:io';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../main.dart';
import '../services/odometer_vision_service.dart';

/// The primary trip-start form widget — sits in the bottom third of Home.
///
/// Holds an odometer field (auto-focused, numeric keyboard), a camera button
/// for OCR, and a location chip (supplied externally by the parent). The
/// [_onStart] callback fires when the user taps _Aloita ajo_ or presses
/// _done_ on the keypad.
class StartCard extends StatefulWidget {
  final int? initialOdometer;
  final bool enabled;
  final String? selectedRouteLabel;
  final VoidCallback onStart;
  final OdometerVisionService? visionService;
  final Widget locationChip;

  const StartCard({
    super.key,
    this.initialOdometer,
    this.enabled = true,
    this.selectedRouteLabel,
    required this.onStart,
    this.visionService,
    required this.locationChip,
  });

  @override
  State<StartCard> createState() => StartCardState();
}

class StartCardState extends State<StartCard> {
  final _odometerFocus = FocusNode();
  final _odometerCtrl = TextEditingController();
  bool _isProcessingOcr = false;
  String? _ocrCaption;
  bool _ocrLowConfidence = false;

  int? get odometerValue {
    final text = _odometerCtrl.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialOdometer != null) {
      _odometerCtrl.text = widget.initialOdometer.toString();
    }
    // Request focus after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.enabled) {
        _odometerFocus.requestFocus();
        if (_odometerCtrl.text.isNotEmpty) {
          _odometerCtrl.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _odometerCtrl.text.length,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _odometerFocus.dispose();
    _odometerCtrl.dispose();
    super.dispose();
  }

  void setOdometer(int value) {
    _odometerCtrl.text = value.toString();
  }

  void clearOdometer() {
    _odometerCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Numeral typography: medium = 32/w600/tabular (spec §8)
    final numeralStyle = Theme.of(
      context,
    ).extension<NumeralTypography>()!.medium;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Selected route label
        if (widget.selectedRouteLabel != null) ...[
          Row(
            children: [
              Icon(Symbols.route, size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.selectedRouteLabel!,
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        // Location chip
        widget.locationChip,
        const SizedBox(height: 8),
        // Odometer row
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: _odometerCtrl,
                focusNode: _odometerFocus,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.done,
                enabled: widget.enabled,
                onSubmitted: (_) => widget.onStart(),
                style: numeralStyle,
                decoration: InputDecoration(
                  labelText: 'Matkamittari (km)',
                  hintText: 'Esim. 123456',
                  // No OutlineInputBorder — use M3 filled style (spec §10b, cross-cutting)
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 56×56 IconButton.filledTonal per spec §2
            SizedBox(
              width: 56,
              height: 56,
              child: IconButton.filledTonal(
                onPressed: _isProcessingOcr ? null : _captureAndOcr,
                icon: _isProcessingOcr
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Symbols.camera_alt),
              ),
            ),
          ],
        ),
        // OCR low-confidence caption (amber, not red errorText — spec §2)
        if (_ocrCaption != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Symbols.warning_amber_rounded,
                size: 14,
                color: _ocrLowConfidence ? Colors.amber.shade700 : null,
              ),
              const SizedBox(width: 4),
              Text(
                _ocrCaption!,
                style: TextStyle(
                  fontSize: 12,
                  color: _ocrLowConfidence
                      ? Colors.amber.shade700
                      : colorScheme.error,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        // Start button
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            onPressed: widget.enabled ? widget.onStart : null,
            icon: const Icon(Symbols.play_arrow),
            label: const Text('Aloita ajo'),
          ),
        ),
      ],
    );
  }

  Future<void> _captureAndOcr() async {
    if (widget.visionService == null) return;

    final photo = await ImagePicker().pickImage(source: ImageSource.camera);
    if (photo == null) return;

    setState(() {
      _isProcessingOcr = true;
      _ocrCaption = null;
    });

    try {
      final result = await widget.visionService!.extractOdometer(
        photo.path,
        expectedHint: widget.initialOdometer,
      );

      if (!mounted) return;

      if (result != null) {
        _odometerCtrl.text = result.value.toString();
        _odometerFocus.requestFocus();
        // Select all so the user can immediately correct (spec §2 done-when)
        _odometerCtrl.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _odometerCtrl.text.length,
        );

        if (result.confidence < 0.7) {
          // Amber caption — non-blocking, user can still type (spec §2)
          setState(() {
            _ocrCaption = 'Tarkista lukema';
            _ocrLowConfidence = true;
          });
        } else {
          setState(() => _ocrCaption = null);
        }
      } else {
        // Failed OCR — non-blocking snackbar, field stays usable (spec §2)
        setState(() {
          _ocrCaption = 'Lukemaa ei tunnistettu — kirjoita käsin';
          _ocrLowConfidence = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lukemaa ei tunnistettu — kirjoita käsin'),
          ),
        );
      }
    } finally {
      try {
        await File(photo.path).delete();
      } catch (_) {}

      if (mounted) setState(() => _isProcessingOcr = false);
    }
  }
}
