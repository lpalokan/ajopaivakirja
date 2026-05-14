import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

typedef OdometerResult = ({int odometer, String? purpose, DateTime? time});

Future<OdometerResult?> showOdometerDialog({
  required BuildContext context,
  required String title,
  String? subtitle,
  String? label,
  required String actionLabel,
  String? relatedField,
  int? initialValue,
  int? expectedHint,
  bool showTime = false,
  DateTime? initialTime,
  String? timeLabel,
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
      initialValue: initialValue,
      expectedHint: expectedHint,
      showTime: showTime,
      initialTime: initialTime,
      timeLabel: timeLabel,
    ),
  );
}

class _OdometerInput extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String? label;
  final String actionLabel;
  final String? relatedField;
  final int? initialValue;
  final int? expectedHint;
  final bool showTime;
  final DateTime? initialTime;
  final String? timeLabel;

  const _OdometerInput({
    required this.title,
    this.subtitle,
    this.label,
    required this.actionLabel,
    this.relatedField,
    this.initialValue,
    this.expectedHint,
    this.showTime = false,
    this.initialTime,
    this.timeLabel,
  });

  @override
  State<_OdometerInput> createState() => _OdometerInputState();
}

class _OdometerInputState extends State<_OdometerInput> {
  final _odometerController = TextEditingController();
  final _purposeController = TextEditingController();
  late DateTime _pickedTime;
  bool _hasRelatedField = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _hasRelatedField = widget.relatedField != null;
    if (widget.initialValue != null) {
      _odometerController.text = widget.initialValue.toString();
    }
    _pickedTime = widget.initialTime ?? DateTime.now();
  }

  @override
  void dispose() {
    _odometerController.dispose();
    _purposeController.dispose();
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

    setState(() => _errorText = null);
    final purpose =
        _hasRelatedField ? _purposeController.text.trim() : null;
    final time = widget.showTime ? _pickedTime : null;

    Navigator.pop(context, (odometer: value, purpose: purpose, time: time));
  }
}
