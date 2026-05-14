import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'log_service.dart';

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
    final candidates = <int>{};

    for (final block in blocks) {
      final text = block.text;
      if (text.isEmpty) continue;

      // Pattern 1: numbers with thousand separators (space or dot)
      // e.g. "123 456", "12.345", "123 456.7" → 123456, 12345, 123456
      for (final m
          in RegExp(r'\b\d{1,3}(?:[ .]\d{3})+\b').allMatches(text)) {
        final digits = m.group(0)!.replaceAll(RegExp(r'[ .]'), '');
        final value = int.tryParse(digits);
        if (value != null && value >= 100 && value < 10000000) {
          candidates.add(value);
        }
      }

      // Pattern 2: bare digit sequences of 5-7 digits
      // e.g. "123456", "12345" — word boundaries prevent partial matches
      for (final m in RegExp(r'\b\d{5,7}\b').allMatches(text)) {
        final value = int.tryParse(m.group(0)!);
        if (value != null && value >= 100 && value < 10000000) {
          candidates.add(value);
        }
      }
    }

    if (candidates.isEmpty) return null;

    final sorted = candidates.toList();
    if (expectedHint != null) {
      sorted.sort(
          (a, b) => (a - expectedHint).abs().compareTo((b - expectedHint).abs()));
    } else {
      sorted.sort(
          (a, b) => b.toString().length.compareTo(a.toString().length));
    }

    LogService().info(
        'OCR candidates (blocks): $sorted${expectedHint != null ? ' hint=$expectedHint' : ''}');
    return sorted.first;
  }

  void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
  }
}
