/// Parsing for user-entered decimals in the Finnish locale, where the decimal
/// separator may be a comma ("0,55") or a dot ("0.55").
///
/// This `trim → replace comma → tryParse` dance was copy-pasted across the
/// settings, route and expense dialogs (each with its own fallback). Centralised
/// here it is one rule, unit-tested, so the dialogs can't drift apart.
library;

/// Parse [input] as a decimal, accepting comma or dot as the separator.
/// Returns null for blank or non-numeric input.
double? parseDecimal(String input) {
  final cleaned = input.trim().replaceAll(',', '.');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

/// Like [parseDecimal] but returns [fallback] when the input is blank or
/// non-numeric.
double parseDecimalOr(String input, double fallback) =>
    parseDecimal(input) ?? fallback;
