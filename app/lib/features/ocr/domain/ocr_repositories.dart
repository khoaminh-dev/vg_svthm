import 'ocr_models.dart';

/// Đọc số liệu từ ảnh. Có hai cách: ML Kit trên máy (miễn phí, nhanh) và AI qua `/api/ocr` (chính xác hơn với
/// màn hình LCD, hoá đơn, bảng biểu).
abstract interface class OcrEngine {
  Future<OcrScan> scan(String imagePath);
}

/// Lưu và đọc kết quả OCR (Supabase).
abstract interface class OcrRepository {
  Future<List<OcrRecord>> list();

  /// Tải ảnh lên Storage rồi lưu bản ghi.
  Future<OcrRecord> save({
    required String title,
    required String rawText,
    required List<OcrValue> values,
    required String localImagePath,
  });

  Future<void> delete(OcrRecord record);

  /// Link tạm thời để xem ảnh đã lưu (bucket riêng tư).
  Future<String?> imageUrl(OcrRecord record);
}
