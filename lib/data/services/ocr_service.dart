import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../domain/menu_logic/menu_line_parser.dart';

/// What the recogniser read from one photo.
class OcrResult {
  const OcrResult({required this.text, required this.lines});

  /// All recognised text, as one string (kept with the photo as `ocr_text`).
  final String text;
  final List<OcrLine> lines;
}

abstract interface class OcrService {
  /// Reads the text of the image file at [imagePath] on the device (no network).
  Future<OcrResult> recognize(String imagePath);
}

/// ML Kit on-device text recognition, Latin script only (D29: Arabic menus fall
/// back to typing it yourself).
class MlKitOcrService implements OcrService {
  @override
  Future<OcrResult> recognize(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(imagePath),
      );
      return OcrResult(
        text: result.text,
        lines: [
          for (final block in result.blocks)
            for (final line in block.lines)
              OcrLine(line.text, confidence: line.confidence),
        ],
      );
    } finally {
      await recognizer.close();
    }
  }
}

final ocrServiceProvider = Provider<OcrService>((ref) => MlKitOcrService());
