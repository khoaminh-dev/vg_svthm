import 'bp_models.dart';

abstract interface class BpRepository {
  /// Các lần đo gần nhất, mới nhất trước.
  Future<List<BpReading>> list({int limit = 200});

  Future<void> add(BpReading reading);

  Future<void> delete(String id);
}
