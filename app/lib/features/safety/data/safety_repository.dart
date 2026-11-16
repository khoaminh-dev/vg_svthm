import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../domain/safety_models.dart';

abstract interface class SafetyRepository {
  /// Chủ bấm SOS. Trả về id (trong 2 phút bấm lại trả về cái cũ).
  Future<String> triggerSos();

  /// Con nhận SOS: `ok` hoặc `already` (đã có người nhận).
  Future<String> ackSos(String id);

  /// Chủ huỷ SOS bấm nhầm: `ok` hoặc `already`.
  Future<String> cancelSos(String id);

  Future<SosEvent?> sos(String id);

  /// Các SOS đang mở của những người tôi theo dõi (RLS tự lọc theo quyền `alerts`).
  Future<List<SosEvent>> openSos();

  Future<EmergencyCard?> card(String ownerId);

  Future<void> saveCard(String ownerId, EmergencyCard card);
}

class SupabaseSafetyRepository implements SafetyRepository {
  SupabaseSafetyRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<String> triggerSos() => _guard(() async {
    final id = await _client.rpc('trigger_sos');
    return id as String;
  });

  @override
  Future<String> ackSos(String id) => _guard(() async {
    final r = await _client.rpc('ack_sos', params: {'p_id': id});
    return r as String;
  });

  @override
  Future<String> cancelSos(String id) => _guard(() async {
    final r = await _client.rpc('cancel_sos', params: {'p_id': id});
    return r as String;
  });

  @override
  Future<SosEvent?> sos(String id) => _guard(() async {
    final row = await _client
        .from('sos_events')
        .select()
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : SosEvent.fromMap(row);
  });

  @override
  Future<List<SosEvent>> openSos() => _guard(() async {
    final me = _client.auth.currentUser?.id;
    final rows = await _client
        .from('sos_events')
        .select()
        .eq('status', 'open')
        .gt(
          'created_at',
          DateTime.now()
              .toUtc()
              .subtract(const Duration(hours: 12))
              .toIso8601String(),
        )
        .order('created_at', ascending: false);
    return [
      for (final r in rows)
        if (r['owner_id'] != me) SosEvent.fromMap(r),
    ];
  });

  @override
  Future<EmergencyCard?> card(String ownerId) => _guard(() async {
    final row = await _client
        .from('emergency_cards')
        .select()
        .eq('owner_id', ownerId)
        .maybeSingle();
    return row == null ? null : EmergencyCard.fromMap(row);
  });

  @override
  Future<void> saveCard(String ownerId, EmergencyCard card) => _guard(() async {
    await _client.rpc(
      'save_emergency_card',
      params: {'p_owner': ownerId, 'p_card': card.toMap()},
    );
  });

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on AppFailure {
      rethrow;
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        throw const AppFailure('Bạn không có quyền làm việc này');
      }
      if (e.code == '22023') {
        throw const AppFailure('Thông tin chưa hợp lệ, hãy kiểm tra số điện thoại và nhóm máu');
      }
      throw AppFailure('Chưa làm được (${e.message})');
    } catch (_) {
      throw const AppFailure('Không kết nối được máy chủ, hãy kiểm tra mạng');
    }
  }
}
