import 'bp_models.dart';

abstract interface class BpRepository {
  /// Các lần đo gần nhất, mới nhất trước.
  Future<List<BpReading>> list({int limit = 200, String? ownerId});

  Future<void> add(BpReading reading);

  Future<void> delete(String id);

  /// Ghi triệu chứng người dùng báo cho cả phiên đo (`none` nếu không có).
  Future<void> markSymptoms(String sessionId, List<String> symptoms);

  /// Ghi lại bối cảnh của cả phiên đo (ví dụ thêm `irregular_pulse`).
  Future<void> markContext(String sessionId, List<String> context);
}
