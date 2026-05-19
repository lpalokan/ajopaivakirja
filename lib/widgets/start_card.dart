import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
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
  String? _ocrWarning;

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
    final numeralMedium = Theme.of(context)
        .textTheme
        .displaySmall
        ?.copyWith(fontSize: 32, fontWeight: FontWeight.w600);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Selected route label
        if (widget.selectedRouteLabel != null) ...[
          Row(
            children: [
              Icon(Icons.route, size: 16, color: colorScheme.primary),
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
                style: numeralMedium,
                decoration: InputDecoration(
                  labelText: 'Matkamittari (km)',
                  hintText: 'Esim. 123456',
                  border: const OutlineInputBorder(),
                  errorText: _ocrWarning,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 56,
              height: 56,
              child: FilledButton.tonalIcon(
                onPressed: _isProcessingOcr ? null : _captureAndOcr,
                icon: _isProcessingOcr
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.camera_alt),
                label: const SizedBox.shrink(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Start button
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            onPressed: widget.enabled ? widget.onStart : null,
            icon: const Icon(Icons.play_arrow),
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
      _ocrWarning = null;
    });

    try {
      final reading = await widget.visionService!.extractOdometer(
        photo.path,
        expectedHint: widget.initialOdometer,
      );

      if (!mounted) return;

      if (reading != null) {
        _odometerCtrl.text = reading.toString();
        _odometerFocus.requestFocus();
        if (reading < 0.7) {
          // Using null confidence means we just show the result
          setState(() => _ocrWarning = null);
        }
      } else {
        setState(
            () => _ocrWarning = 'Lukemaa ei tunnistettu — kirjoita käsin');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Lukemaa ei tunnistettu — kirjoita käsin')),
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
