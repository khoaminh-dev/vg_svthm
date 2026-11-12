import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../../core/errors/app_failure.dart';
import '../domain/ocr_models.dart';
import '../domain/ocr_parser.dart';
import '../domain/ocr_repositories.dart';

class MlKitOcrEngine implements OcrEngine {
  @override
  Future<OcrScan> scan(String imagePath) async {
    final supported = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (!supported) {
      throw const AppFailure('OCR chỉ hỗ trợ trên Android và iOS');
    }

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(imagePath));
      return OcrScan(rawText: result.text, values: OcrParser.parse(result.text));
    } catch (_) {
      throw const AppFailure('Không đọc được ảnh, hãy thử ảnh rõ hơn');
    } finally {
      await recognizer.close();
    }
  }
}
