import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/expense.dart';

/// Dialog to add or edit an expense for a trip leg.
class ExpenseDialog extends StatefulWidget {
  final Expense? existing;

  const ExpenseDialog({super.key, this.existing});

  @override
  State<ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<ExpenseDialog> {
  ExpenseType _type = ExpenseType.parking;
  final _amountController = TextEditingController();
  final _descController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _type = widget.existing!.type;
      _amountController.text = widget.existing!.amount.toString();
      _descController.text = widget.existing!.description ?? '';
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing != null ? 'Muokkaa kulua' : 'Lisää kulu'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<ExpenseType>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Tyyppi',
                border: OutlineInputBorder(),
              ),
              items: ExpenseType.values.map((t) {
                return DropdownMenuItem(value: t, child: Text(t.displayName));
              }).toList(),
              onChanged: (v) {
                if (v != null) setState(() => _type = v);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Summa (€)',
                suffixText: '€',
                border: OutlineInputBorder(),
              ),
              autofocus: widget.existing == null,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'Kuvaus (valinnainen)',
                hintText: 'esim. Pysäköintitalo Forum',
                border: OutlineInputBorder(),
              ),
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
          onPressed: () {
            final amount = double.tryParse(
              _amountController.text.trim().replaceAll(',', '.'),
            );
            if (amount == null || amount <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Anna kelvollinen summa')),
              );
              return;
            }
            Navigator.pop(context, (
              type: _type,
              amount: amount,
              description: _descController.text.trim().isEmpty
                  ? null
                  : _descController.text.trim(),
            ));
          },
          child: const Text('Tallenna'),
        ),
      ],
    );
  }
}
