import 'package:flutter_test/flutter_test.dart';
import 'package:kilometrikorvaus/services/decimal_input.dart';

void main() {
  group('parseDecimal', () {
    test('parses a dot decimal', () {
      expect(parseDecimal('0.55'), 0.55);
    });

    test('parses a comma decimal (Finnish locale)', () {
      expect(parseDecimal('0,55'), 0.55);
    });

    test('trims surrounding whitespace', () {
      expect(parseDecimal('  12,5 '), 12.5);
    });

    test('parses an integer string', () {
      expect(parseDecimal('200'), 200.0);
    });

    test('returns null for blank input', () {
      expect(parseDecimal(''), isNull);
      expect(parseDecimal('   '), isNull);
    });

    test('returns null for non-numeric input', () {
      expect(parseDecimal('abc'), isNull);
    });
  });

  group('parseDecimalOr', () {
    test('returns the parsed value when valid', () {
      expect(parseDecimalOr('0,57', 0.55), 0.57);
    });

    test('returns the fallback when blank or invalid', () {
      expect(parseDecimalOr('', 0.55), 0.55);
      expect(parseDecimalOr('xyz', 200), 200);
    });
  });
}
