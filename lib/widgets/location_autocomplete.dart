import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

/// Text field with a dropdown of known locations.
///
/// The supplied [controller] is the single source of truth: the field writes
/// typed text straight onto it, picking an option writes onto it, and callers
/// read `controller.text` back when their save button is pressed.
///
/// The menu opens from the arrow and from nowhere else. That is deliberate on
/// both counts:
///
/// - The arrow used to be a bare icon whose only action was
///   `focusNode.requestFocus()` — a no-op on a field that already had focus.
///   And `RawAutocomplete` filtered its options by the field's current text,
///   so on a pre-filled field (editing a route, or the "Muuta sijainti"
///   dialog seeded with the current location) the one gesture that means
///   "show me the list" showed a list of one. Now it always offers
///   everything.
/// - Opening on a tap of the *field* — which is what `DropdownMenu` does —
///   drops the menu over whatever sits below, and in every dialog that is the
///   Peruuta/Käytä buttons. The user's next tap would then dismiss the menu
///   instead of pressing the button they aimed at. Typing must not cost
///   anyone a tap on the primary action.
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
  final MenuController _menu = MenuController();

  /// What the field held when the menu was opened. Typing after that narrows
  /// the list; the text the field arrived with does not, or the arrow would
  /// be back to showing a list of one.
  String _textWhenOpened = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  /// Only rebuild while the menu is open — that is the only time the text can
  /// change what is on screen.
  void _onTextChanged() {
    if (_menu.isOpen && mounted) setState(() {});
  }

  List<String> get _visibleSuggestions {
    final typed = widget.controller.text;
    if (typed == _textWhenOpened || typed.trim().isEmpty) {
      return widget.suggestions;
    }
    final needle = typed.toLowerCase();
    return widget.suggestions
        .where((s) => s.toLowerCase().contains(needle))
        .toList();
  }

  void _toggleMenu() {
    if (_menu.isOpen) {
      _menu.close();
      return;
    }
    setState(() => _textWhenOpened = widget.controller.text);
    _menu.open();
  }

  void _select(String suggestion) {
    widget.controller.value = TextEditingValue(
      text: suggestion,
      selection: TextSelection.collapsed(offset: suggestion.length),
    );
    _menu.close();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _menu,
      menuChildren: [
        for (final suggestion in _visibleSuggestions)
          MenuItemButton(
            onPressed: () => _select(suggestion),
            child: Text(suggestion),
          ),
      ],
      builder: (context, controller, child) => TextField(
        controller: widget.controller,
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: const Icon(Symbols.arrow_drop_down),
            tooltip: 'Näytä tunnetut sijainnit',
            onPressed: _toggleMenu,
          ),
        ),
      ),
    );
  }
}
