import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

/// Text field with a dropdown of known locations.
///
/// The supplied [controller] is the single source of truth: it is passed
/// straight through to the underlying field so typed (or programmatically
/// entered) text always lands on it. The previous implementation kept a
/// second, Autocomplete-owned controller and copied `controller.text` into
/// it on every build, which clobbered freshly entered text before the caller
/// could read it back.
class LocationAutocomplete extends StatefulWidget {
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
  State<LocationAutocomplete> createState() => _LocationAutocompleteState();
}

class _LocationAutocompleteState extends State<LocationAutocomplete> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (textEditingValue) {
        final text = textEditingValue.text.toLowerCase();
        if (text.isEmpty) return widget.suggestions;
        return widget.suggestions.where((s) => s.toLowerCase().contains(text));
      },
      onSelected: (_) {
        // RawAutocomplete already wrote the selection into the shared
        // controller; just close the options overlay.
        FocusManager.instance.primaryFocus?.unfocus();
      },
      fieldViewBuilder: (context, fieldController, focusNode, onFieldSubmitted) {
        return TextField(
          controller: fieldController,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: widget.label,
            border: const OutlineInputBorder(),
            suffixIcon: GestureDetector(
              onTap: () => focusNode.requestFocus(),
              child: const Icon(Symbols.arrow_drop_down),
            ),
          ),
          onSubmitted: (_) => onFieldSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 360),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return InkWell(
                    onTap: () => onSelected(option),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(option),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
