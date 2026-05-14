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

      final result = _findOdometerNumber(recognized.text,
          expectedHint: expectedHint);
      if (result != null) {
        LogService().info('OCR: extracted odometer reading $result');
      } else {
        LogService()
            .info('OCR: no odometer-like number found in "${recognized.text}"');
      }
      return result;
    } catch (e, st) {
      LogService().error('OCR: extraction failed', e, st);
      return null;
    }
  }

  int? _findOdometerNumber(String text, {int? expectedHint}) {
    final cleaned = text.replaceAll(RegExp(r'[\s,.]'), '');

    final matches = RegExp(r'\d{5,7}').allMatches(cleaned);
    final candidates = matches
        .map((m) => int.parse(m.group(0)!))
        .where((n) => n > 0)
        .toList();

    if (candidates.isEmpty) return null;

    if (expectedHint != null) {
      candidates.sort(
          (a, b) => (a - expectedHint).abs().compareTo((b - expectedHint).abs()));
    } else {
      candidates.sort(
          (a, b) => b.toString().length.compareTo(a.toString().length));
    }

    return candidates.first;
  }

  void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
  }
}
