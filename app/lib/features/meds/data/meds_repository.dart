import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../domain/meds_models.dart';

abstract interface class MedsRepository {
  /// Các đơn của [ownerId] (đang dùng trước, mới nhất trước).
  Future<List<MedPlan>> plans(String ownerId);

  /// Các lần uống có giờ trong [from, to).
  Future<List<Dose>> doses(String ownerId, DateTime from, DateTime to);

  /// Lưu đơn (tạo mới hoặc sửa nếu có id). [replace] = kết thúc các đơn đang dùng khác. Trả về id đơn.
  Future<String> savePlan(String ownerId, MedPlan plan, {bool replace = false});

  Future<void> endPlan(String planId);

  /// `taken`, `skipped`, hoặc `pending` (hoàn tác trong 2 giờ).
  Future<void> setDose(String doseId, String status);

  Future<void> snooze(String doseId, int minutes);
}

class SupabaseMedsRepository implements MedsRepository {
  SupabaseMedsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<MedPlan>> plans(String ownerId) => _guard(() async {
    final rows = await _client
        .from('med_plans')
        .select('*, med_slots(*, med_items(*)), med_prn(*)')
        .eq('owner_id', ownerId)
        .order('created_at', ascending: false);
    final list = [for (final r in rows) MedPlan.fromJson(r)];
    list.sort((a, b) => a.active == b.active ? 0 : (a.active ? -1 : 1));
    return list;
  });

  @override
  Future<List<Dose>> doses(String ownerId, DateTime from, DateTime to) =>
      _guard(() async {
        final rows = await _client
            .from('dose_events')
            .select()
            .eq('owner_id', ownerId)
            .gte('due_at', from.toUtc().toIso8601String())
            .lt('due_at', to.toUtc().toIso8601String())
            .order('due_at', ascending: true);
        return [for (final r in rows) Dose.fromJson(r)]
          ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
      });

  @override
  Future<String> savePlan(
    String ownerId,
    MedPlan plan, {
    bool replace = false,
  }) => _guard(() async {
    final id = await _client.rpc(
      'save_med_plan',
      params: {
        'p_owner': ownerId,
        'p_plan': plan.toJson(),
        'p_replace': replace,
      },
    );
    return id as String;
  });

  @override
  Future<void> endPlan(String planId) => _guard(() async {
    await _client.rpc('end_med_plan', params: {'p_plan': planId});
  });

  @override
  Future<void> setDose(String doseId, String status) => _guard(() async {
    await _client.rpc(
      'set_dose',
      params: {'p_event': doseId, 'p_status': status},
    );
  });

  @override
  Future<void> snooze(String doseId, int minutes) => _guard(() async {
    await _client.rpc(
      'set_dose',
      params: {'p_event': doseId, 'p_snooze_min': minutes},
    );
  });

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on AppFailure {
      rethrow;
    } on PostgrestException catch (e) {
      if (e.code == '42501')
        throw const AppFailure('Bạn không có quyền sửa lịch thuốc này');
      if (e.message.contains('cannot_undo'))
        throw const AppFailure('Đã quá 2 giờ nên không hoàn tác được');
      if (e.message.contains('too_many'))
        throw const AppFailure('Quá nhiều cữ hoặc thuốc trong một đơn');
      throw AppFailure('Chưa làm được (${e.message})');
    } catch (_) {
      throw const AppFailure('Lỗi kết nối, vui lòng thử lại');
    }
  }
}
