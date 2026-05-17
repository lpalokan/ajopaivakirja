import 'package:flutter/material.dart';

/// Text field with a dropdown of known locations.
///
/// Selecting a suggestion writes it to [controller] and unfocuses the field
/// so the options overlay closes instead of lingering on screen.
class LocationAutocomplete extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final List<String> suggestions;

  const LocationAutocomplete({
    super.key,
    required this.controller,
    required this.label,
    required this.suggestions,
  });

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      optionsBuilder: (textEditingValue) {
        final text = textEditingValue.text.toLowerCase();
        if (text.isEmpty) return suggestions;
        return suggestions.where((s) => s.toLowerCase().contains(text));
      },
      onSelected: (value) {
        controller.text = value;
        controller.selection = TextSelection.fromPosition(
          TextPosition(offset: value.length),
        );
        // Close the options overlay: it stays open while the field keeps
        // focus and the (now-matching) suggestion list is non-empty.
        FocusManager.instance.primaryFocus?.unfocus();
      },
      fieldViewBuilder: (context, autocompleteCtrl, focusNode, onSubmitted) {
        autocompleteCtrl.text = controller.text;
        return TextField(
          controller: autocompleteCtrl,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            suffixIcon: GestureDetector(
              onTap: () => focusNode.requestFocus(),
              child: const Icon(Icons.arrow_drop_down),
            ),
          ),
          onChanged: (v) {
            controller.text = v;
          },
        );
      },
    );
  }
}
