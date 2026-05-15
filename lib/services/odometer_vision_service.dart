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

  static const _gaugeNumbers = {
    20, 30, 40, 50, 60, 70, 80, 90,
    100, 110, 120, 130, 140, 150, 160, 170, 180, 190, 200,
    210, 220, 240, 260, 280, 300,
  };

  static bool _isGaugeComposite(String rawMatch) {
    final parts = rawMatch
        .split(RegExp(r'[ .]'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.length < 2) return false;
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || !_gaugeNumbers.contains(n)) return false;
    }
    return true;
  }

  static bool _hasGaugeProgression(String text) {
    final numbers = RegExp(r'\b\d+\b')
        .allMatches(text)
        .map((m) => int.parse(m.group(0)!))
        .toSet()
        .toList();
    if (numbers.length < 3) return false;
    numbers.sort();

    for (int i = 0; i < numbers.length - 2; i++) {
      final step = numbers[i + 1] - numbers[i];
      if (step != 10 && step != 20 && step != 40) continue;
      if (numbers[i + 2] - numbers[i + 1] == step) return true;
    }
    return false;
  }

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
      final tokenCount = RegExp(r'\b\d+\b').allMatches(text).length;

      int blockModifier = 0;

      if (RegExp(r'km\s*/?\s*h\b|mph\b|rpm\b|r\s*/?\s*min\b',
              caseSensitive: false)
          .hasMatch(text)) {
        blockModifier -= 10;
      }

      if (lower.contains('odo') || lower.contains('total')) {
        blockModifier += 10;
      }

      if (tokenCount >= 5) {
        blockModifier -= 10;
      } else if (tokenCount >= 3) {
        blockModifier -= 3;
      }

      if (_hasGaugeProgression(text)) {
        blockModifier -= 10;
      }

      final blockCandidates = <int>{};
      final gaugePenalty = <int, int>{};

      for (final m
          in RegExp(r'\b\d{1,3}(?:[ .]\d{3})+?\b').allMatches(text)) {
        final rawMatch = m.group(0)!;
        final digits = rawMatch.replaceAll(RegExp(r'[ .]'), '');
        if (digits.length >= 5) {
          final value = int.tryParse(digits);
          if (value != null && value >= 100 && value < 10000000) {
            blockCandidates.add(value);
            if (_isGaugeComposite(rawMatch)) {
              gaugePenalty[value] = -10;
            }
          }
        }
      }

      for (final m in RegExp(r'\b\d{5,7}\b').allMatches(text)) {
        final value = int.tryParse(m.group(0)!);
        if (value != null && value >= 100 && value < 10000000) {
          blockCandidates.add(value);
        }
      }

      for (final value in blockCandidates) {
        final numDigits = value.toString().length;
        int score = blockModifier + (gaugePenalty[value] ?? 0);

        if (numDigits == 6) {
          score += 3;
        } else if (numDigits == 7) {
          score += 2;
        } else if (numDigits == 5) {
          score += 1;
        }

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
      LogService().info(
          'OCR: best candidate score ${sorted.first.score} < 0, rejecting');
      return null;
    }

    return sorted.first.value;
  }

  void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
  }
}
