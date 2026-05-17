import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../services/odometer_vision_service.dart';
import 'location_autocomplete.dart';

typedef OdometerResult = ({
  int odometer,
  String? purpose,
  DateTime? time,
  String? location,
});

Future<OdometerResult?> showOdometerDialog({
  required BuildContext context,
  required String title,
  String? subtitle,
  String? label,
  required String actionLabel,
  String? relatedField,
  String? initialPurpose,
  int? initialValue,
  int? expectedHint,
  bool showTime = false,
  DateTime? initialTime,
  String? timeLabel,
  String? locationLabel,
  String? initialLocation,
  List<String> locationSuggestions = const [],
  OdometerVisionService? visionService,
}) {
  return showDialog<OdometerResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _OdometerInput(
      title: title,
      subtitle: subtitle,
      label: label,
      actionLabel: actionLabel,
      relatedField: relatedField,
      initialPurpose: initialPurpose,
      initialValue: initialValue,
      expectedHint: expectedHint,
      showTime: showTime,
      initialTime: initialTime,
      timeLabel: timeLabel,
      locationLabel: locationLabel,
      initialLocation: initialLocation,
      locationSuggestions: locationSuggestions,
      visionService: visionService,
    ),
  );
}

class _OdometerInput extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String? label;
  final String actionLabel;
  final String? relatedField;
  final String? initialPurpose;
  final int? initialValue;
  final int? expectedHint;
  final bool showTime;
  final DateTime? initialTime;
  final String? timeLabel;
  final String? locationLabel;
  final String? initialLocation;
  final List<String> locationSuggestions;
  final OdometerVisionService? visionService;

  const _OdometerInput({
    required this.title,
    this.subtitle,
    this.label,
    required this.actionLabel,
    this.relatedField,
    this.initialPurpose,
    this.initialValue,
    this.expectedHint,
    this.showTime = false,
    this.initialTime,
    this.timeLabel,
    this.locationLabel,
    this.initialLocation,
    this.locationSuggestions = const [],
    this.visionService,
  });

  @override
  State<_OdometerInput> createState() => _OdometerInputState();
}

class _OdometerInputState extends State<_OdometerInput> {
  final _odometerController = TextEditingController();
  final _purposeController = TextEditingController();
  final _locationController = TextEditingController();
  late DateTime _pickedTime;
  bool _hasRelatedField = false;
  bool _hasLocationField = false;
  String? _errorText;
  bool _isProcessingOcr = false;

  @override
  void initState() {
    super.initState();
    _hasRelatedField = widget.relatedField != null;
    _hasLocationField = widget.locationLabel != null;
    if (widget.initialLocation != null) {
      _locationController.text = widget.initialLocation!;
    }
    if (widget.initialValue != null) {
      _odometerController.text = widget.initialValue.toString();
    }
    if (widget.initialPurpose != null) {
      _purposeController.text = widget.initialPurpose!;
    }
    _pickedTime = widget.initialTime ?? DateTime.now();
  }

  @override
  void dispose() {
    _odometerController.dispose();
    _purposeController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final timeFmt = DateFormat('HH:mm');

    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.subtitle != null) ...[
              Text(widget.subtitle!,
                  style: TextStyle(color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 16),
            ],
            if (widget.showTime) ...[
              InkWell(
                onTap: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(_pickedTime),
                  );
                  if (t != null) {
                    setState(() {
                      _pickedTime = DateTime(
                        _pickedTime.year,
                        _pickedTime.month,
                        _pickedTime.day,
                        t.hour,
                        t.minute,
                      );
                    });
                  }
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: widget.timeLabel ?? 'Aika',
                    border: const OutlineInputBorder(),
                    suffixIcon: const Icon(Icons.access_time),
                  ),
                  child: Text(timeFmt.format(_pickedTime)),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_hasLocationField) ...[
              LocationAutocomplete(
                controller: _locationController,
                label: widget.locationLabel!,
                suggestions: widget.locationSuggestions,
              ),
              const SizedBox(height: 16),
            ],
            if (_hasRelatedField) ...[
              TextField(
                controller: _purposeController,
                decoration: InputDecoration(
                  labelText: widget.relatedField,
                  border: const OutlineInputBorder(),
                  hintText: widget.relatedField == 'Tarkoitus'
                      ? 'Esim. asiakastapaaminen'
                      : null,
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _odometerController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: widget.label ?? 'Matkamittari (km)',
                border: const OutlineInputBorder(),
                hintText: widget.expectedHint != null
                    ? 'Arvioitu: ${widget.expectedHint} km'
                    : 'Esim. 123456',
                errorText: _errorText,
                suffixIcon: widget.visionService != null
                    ? _isProcessingOcr
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.camera_alt),
                            tooltip: 'Ota kuva mittarista',
                            onPressed: _captureAndOcr,
                          )
                    : null,
              ),
              autofocus: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Peruuta'),
        ),
        FilledButton(
          onPressed: _confirm,
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }

  void _confirm() {
    final odometerText = _odometerController.text.trim();
    if (odometerText.isEmpty) {
      setState(() => _errorText = 'Syötä mittarilukema');
      return;
    }

    final value = int.tryParse(odometerText);
    if (value == null) {
      setState(() => _errorText = 'Virheellinen lukema');
      return;
    }

    final location =
        _hasLocationField ? _locationController.text.trim() : null;
    if (_hasLocationField && (location == null || location.isEmpty)) {
      setState(() => _errorText = 'Syötä ${widget.locationLabel?.toLowerCase()}');
      return;
    }

    setState(() => _errorText = null);
    final purpose =
        _hasRelatedField ? _purposeController.text.trim() : null;
    final time = widget.showTime ? _pickedTime : null;

    Navigator.pop(context,
        (odometer: value, purpose: purpose, time: time, location: location));
  }

  Future<void> _captureAndOcr() async {
    if (widget.visionService == null) return;

    final photo = await ImagePicker().pickImage(source: ImageSource.camera);
    if (photo == null) return;

    setState(() => _isProcessingOcr = true);

    try {
      final reading = await widget.visionService!.extractOdometer(
        photo.path,
        expectedHint: widget.expectedHint,
      );

      if (!mounted) return;

      if (reading != null) {
        _odometerController.text = reading.toString();
        setState(() => _errorText = null);
      } else {
        setState(
            () => _errorText = 'Mittarilukemaa ei tunnistettu, syötä käsin');
      }
    } finally {
      try {
        await File(photo.path).delete();
      } catch (_) {}

      if (mounted) setState(() => _isProcessingOcr = false);
    }
  }
}
