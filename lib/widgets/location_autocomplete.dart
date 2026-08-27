import 'package:flutter/material.dart';

/// Text field with a dropdown of known locations.
///
/// The supplied [controller] is the single source of truth: it is passed
/// straight through to the underlying [DropdownMenu] so typed, picked, or
/// programmatically entered text always lands on it, and callers can read
/// `controller.text` back at any time.
///
/// Built on [DropdownMenu] rather than `RawAutocomplete` because the arrow
/// has to *work*. With `RawAutocomplete` the suffix arrow could only request
/// focus, so tapping it while the field was already focused did nothing at
/// all — and when the field arrives pre-filled (editing a route, or the
/// "Muuta sijainti" dialog seeded with the current location) the option list
/// was filtered down by that pre-filled text, so the one gesture that means
/// "show me the list" showed a list of one, or none. `DropdownMenu`'s
/// trailing button toggles the menu and deliberately drops the filter while
/// doing so, which is exactly the intent.
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
    return DropdownMenu<String>(
      controller: controller,
      label: Text(label),
      // Free text is the point: a location that has never been visited must
      // still be typeable. requestFocusOnTap keeps the keyboard available,
      // enableFilter narrows the list as the user types, and picking from
      // the list stays a shortcut rather than the only way in.
      requestFocusOnTap: true,
      enableFilter: true,
      enableSearch: true,
      // Fill the parent's width. Without this the menu sizes itself to its
      // widest entry, which inside an AlertDialog leaves the field visibly
      // narrower than the plain TextFields it sits between.
      expandedInsets: EdgeInsets.zero,
      menuHeight: 240,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      dropdownMenuEntries: [
        for (final suggestion in suggestions)
          DropdownMenuEntry<String>(value: suggestion, label: suggestion),
      ],
    );
  }
}
