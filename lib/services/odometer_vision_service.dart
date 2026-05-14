import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'log_service.dart';

class _Candidate {
  final int value;
  final int score;
  final int numDigits;

  _Candidate(this.value, this.score, this.numDigits);
}

class OdometerVisionService {
  TextRecognizer? _textRecognizer;

  Future<int?> extractOdometer(String imagePath, {int? expectedHint}) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        LogService().warn('OCR: temp photo file not found at $imagePath');
        return null;
      }

      final inputImage = InputImage.fromFilePath(imagePath);
      _textRecognizer ??=
          TextRecognizer(script: TextRecognitionScript.latin);
      final recognized = await _textRecognizer!.processImage(inputImage);

      if (recognized.text.isEmpty) {
        LogService().info('OCR: no text recognized');
        return null;
      }

      LogService().info(
          'OCR: found ${recognized.blocks.length} block(s) in image');

      final result =
          _findOdometerNumber(recognized.blocks, expectedHint: expectedHint);
      if (result != null) {
        LogService().info('OCR: extracted odometer reading $result');
      } else {
        LogService()
            .info('OCR: no odometer-like number found (checked per-block)');
      }
      return result;
    } catch (e, st) {
      LogService().error('OCR: extraction failed', e, st);
      return null;
    }
  }

  int? _findOdometerNumber(List<TextBlock> blocks, {int? expectedHint}) {
    final candidates = <int, _Candidate>{};

    for (final block in blocks) {
      final text = block.text;
      if (text.isEmpty) continue;

      final lower = text.toLowerCase();

      // Count number tokens in this block for density penalty.
      // Scale-like blocks have many number tokens (20 40 60 80 100...).
      final tokenCount = RegExp(r'\b\d+\b').allMatches(text).length;

      int blockModifier = 0;

      // Speed-related keywords → strong penalty
      if (RegExp(r'km\s*/?\s*h\b|mph\b|rpm\b|r\s*/?\s*min\b',
              caseSensitive: false)
          .hasMatch(text)) {
        blockModifier -= 10;
      }

      // Odometer-related keywords → strong bonus
      if (lower.contains('odo') || lower.contains('total')) {
        blockModifier += 10;
      }

      // Token density: many numbers signal a scale (speedo, tach),
      // not an odometer display
      if (tokenCount >= 5) {
        blockModifier -= 10;
      } else if (tokenCount >= 3) {
        blockModifier -= 3;
      }

      final blockCandidates = <int>{};

      // Pattern 1: numbers with thousand separators (space or dot)
      // e.g. "123 456", "12.345" → 123456, 12345
      // Uses non-greedy +? to avoid consuming an entire speedo scale
      for (final m
          in RegExp(r'\b\d{1,3}(?:[ .]\d{3})+?\b').allMatches(text)) {
        final digits = m.group(0)!.replaceAll(RegExp(r'[ .]'), '');
        if (digits.length >= 5) {
          final value = int.tryParse(digits);
          if (value != null && value >= 100 && value < 10000000) {
            blockCandidates.add(value);
          }
        }
      }

      // Pattern 2: bare digit sequences of 5-7 digits
      // Word boundaries prevent partial matches on longer runs
      for (final m in RegExp(r'\b\d{5,7}\b').allMatches(text)) {
        final value = int.tryParse(m.group(0)!);
        if (value != null && value >= 100 && value < 10000000) {
          blockCandidates.add(value);
        }
      }

      for (final value in blockCandidates) {
        final numDigits = value.toString().length;
        int score = blockModifier;

        // Digit length: 6 digits is the most common odometer format
        if (numDigits == 6) {
          score += 3;
        } else if (numDigits == 7) {
          score += 2;
        } else if (numDigits == 5) {
          score += 1;
        }

        // Proximity to expected reading (e.g. last known odometer)
        if (expectedHint != null) {
          final diff = (value - expectedHint).abs();
          if (diff < 1000) {
            score += 5;
          } else if (diff < 10000) {
            score += 2;
          } else if (diff > 50000) {
            score -= 5;
          }
        }

        // Keep the highest-scoring instance of each value
        if (!candidates.containsKey(value) ||
            score > candidates[value]!.score) {
          candidates[value] = _Candidate(value, score, numDigits);
        }
      }
    }

    if (candidates.isEmpty) return null;

    final sorted = candidates.values.toList()
      ..sort((a, b) {
        final cmp = b.score.compareTo(a.score);
        if (cmp != 0) return cmp;
        return b.numDigits.compareTo(a.numDigits);
      });

    LogService().info(
        'OCR candidates (scored): ${sorted.map((c) => '${c.value}(s${c.score})').join(', ')}'
        '${expectedHint != null ? ' hint=$expectedHint' : ''}');

    if (sorted.first.score < 0) {
      LogService().info('OCR: best candidate score ${sorted.first.score} < 0, rejecting');
      return null;
    }

    return sorted.first.value;
  }

  void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
  }
}
