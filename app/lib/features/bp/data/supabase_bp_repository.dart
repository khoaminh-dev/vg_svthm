import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../domain/bp_models.dart';
import '../domain/bp_repository.dart';

class SupabaseBpRepository implements BpRepository {
  SupabaseBpRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<BpReading>> list({int limit = 200}) => _guard(() async {
    final rows = await _client
        .from('bp_readings')
        .select()
        .order('measured_at', ascending: false)
        .limit(limit);
    return rows.map(BpReading.fromMap).toList();
  });

  @override
  Future<void> add(BpReading reading) => _guard(() async {
    await _client.from('bp_readings').insert(reading.toInsert());
  });

  @override
  Future<void> delete(String id) => _guard(() async {
    await _client.from('bp_readings').delete().eq('id', id);
  });

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on PostgrestException catch (e) {
      throw AppFailure('Không lưu/đọc được dữ liệu huyết áp (${e.message})');
    } catch (_) {
      throw const AppFailure('Lỗi kết nối, vui lòng thử lại');
    }
  }
}
