import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../domain/bp_models.dart';
import '../domain/bp_repository.dart';

class SupabaseBpRepository implements BpRepository {
  SupabaseBpRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<BpReading>> list({int limit = 200, String? ownerId}) =>
      _guard(() async {
        // Luôn lọc theo chủ dữ liệu: người chăm sóc đọc được thêm số đo của cha mẹ, không được lẫn vào danh sách của chính mình.
        final id = ownerId ?? _client.auth.currentUser?.id;
        if (id == null) throw const AppFailure('Phiên đăng nhập đã hết hạn');
        final rows = await _client
            .from('bp_readings')
            .select()
            .eq('user_id', id)
            .order('measured_at', ascending: false)
            .limit(limit);
        return rows.map(BpReading.fromMap).toList();
      });

  @override
  Future<void> add(BpReading reading) => _guard(() async {
    try {
      await _client.from('bp_readings').insert(reading.toInsert());
    } on PostgrestException catch (e) {
      // Máy chủ chưa có cột của phiên đo (migration 0035): vẫn lưu số đo theo cách cũ, không mất dữ liệu.
      if (e.code == 'PGRST204' || e.code == '42703') {
        await _client.from('bp_readings').insert(reading.toLegacyInsert());
        return;
      }
      rethrow;
    }
  });

  @override
  Future<void> markSymptoms(String sessionId, List<String> symptoms) =>
      _guard(() async {
        await _client
            .from('bp_readings')
            .update({'symptoms': symptoms})
            .eq('session_id', sessionId);
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
