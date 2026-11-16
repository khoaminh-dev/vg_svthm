import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../domain/family_models.dart';

abstract interface class FamilyRepository {
  /// Liên kết của tôi (cả hai chiều), chưa gỡ.
  Future<List<FamilyLink>> myFamily();

  /// Tạo mã mời 6 số (hiệu lực 10 phút). Chỉ người được chăm sóc tạo.
  Future<String> createCode();

  /// Nhập mã của người thân để được theo dõi họ.
  Future<RedeemResult> redeem(String code, Relation relation);

  Future<void> revoke(String linkId);

  /// Chỉ người được chăm sóc đổi quyền hoặc tạm dừng (`active` / `paused`).
  Future<void> setPerms(
    String linkId, {
    Map<String, bool>? perms,
    String? status,
  });

  Future<List<AuditEntry>> audit({int limit = 50});

  /// "Nhờ đo huyết áp": `ok` hoặc `too_soon`.
  Future<String> nudgeMeasure(String ownerId);
}

class SupabaseFamilyRepository implements FamilyRepository {
  SupabaseFamilyRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<FamilyLink>> myFamily() => _guard(() async {
    final rows = await _client.rpc('my_family') as List<dynamic>;
    return [
      for (final r in rows)
        FamilyLink.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  });

  @override
  Future<String> createCode() => _guard(() async {
    final code = await _client.rpc('create_link_code');
    return code as String;
  });

  @override
  Future<RedeemResult> redeem(String code, Relation relation) =>
      _guard(() async {
        final rows = await _client.rpc(
          'redeem_link_code',
          params: {'p_code': code, 'p_relation': relation.code},
        ) as List<dynamic>;
        final r = Map<String, dynamic>.from(rows.first as Map);
        return RedeemResult(
          linkId: r['link_id'] as String?,
          error: r['error'] as String?,
        );
      });

  @override
  Future<void> revoke(String linkId) => _guard(() async {
    await _client.rpc('revoke_link', params: {'p_link': linkId});
  });

  @override
  Future<void> setPerms(
    String linkId, {
    Map<String, bool>? perms,
    String? status,
  }) => _guard(() async {
    await _client.rpc(
      'set_link_perms',
      params: {'p_link': linkId, 'p_perms': perms, 'p_status': status},
    );
  });

  @override
  Future<List<AuditEntry>> audit({int limit = 50}) => _guard(() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AppFailure('Phiên đăng nhập đã hết hạn');
    final rows = await _client
        .from('family_audit')
        .select('id, actor_id, action, detail, at')
        .eq('owner_id', uid)
        .order('at', ascending: false)
        .limit(limit);
    final ids = {
      for (final r in rows)
        if (r['actor_id'] != null) r['actor_id'] as String,
    }.toList();
    final names = <String, String>{};
    if (ids.isNotEmpty) {
      final profs = await _client
          .from('profiles')
          .select('id, display_name, username')
          .inFilter('id', ids);
      for (final p in profs) {
        final n = (p['display_name'] as String?)?.trim();
        names[p['id'] as String] = (n != null && n.isNotEmpty)
            ? n
            : (p['username'] as String? ?? 'Người thân');
      }
    }
    return [
      for (final r in rows)
        AuditEntry(
          id: (r['id'] as num).toInt(),
          action: r['action'] as String,
          at: DateTime.parse(r['at'] as String).toLocal(),
          actorName: names[r['actor_id']],
          detail: Map<String, dynamic>.from((r['detail'] as Map?) ?? const {}),
        ),
    ];
  });

  @override
  Future<String> nudgeMeasure(String ownerId) => _guard(() async {
    final r = await _client.rpc('nudge_measure', params: {'p_owner': ownerId});
    return r as String;
  });

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on AppFailure {
      rethrow;
    } on PostgrestException catch (e) {
      if (e.code == '54000')
        throw const AppFailure(
          'Bạn thao tác quá nhiều lần, chờ một lúc rồi thử lại',
        );
      if (e.code == '42501')
        throw const AppFailure('Bạn không có quyền làm việc này');
      throw AppFailure('Chưa làm được (${e.message})');
    } catch (_) {
      throw const AppFailure('Lỗi kết nối, vui lòng thử lại');
    }
  }
}
