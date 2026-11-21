import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/supabase/supabase_providers.dart';

/// Chuẩn hoá số điện thoại người dùng gõ: bỏ khoảng trắng, dấu chấm, gạch, ngoặc; chỉ nhận 8–15 chữ số, có thể có dấu + đầu.
/// Trả về null nếu không hợp lệ (khớp ràng buộc của bảng `profile_phones`).
String? normalizePhone(String raw) {
  final s = raw.replaceAll(RegExp(r'[\s.\-()]'), '');
  return RegExp(r'^\+?[0-9]{8,15}$').hasMatch(s) ? s : null;
}

/// Số điện thoại cá nhân (bảng riêng `profile_phones`, xem migration 0030): chỉ chính chủ ghi; chính chủ và người thân
/// ĐANG liên kết hoạt động (hai chiều) đọc được. Quyền do máy chủ (RLS) đảm bảo, app không tự lọc.
abstract interface class PhoneRepository {
  /// Số của mình, hoặc null nếu chưa có.
  Future<String?> mine();

  /// Lưu số của mình; [phone] null hoặc rỗng thì xoá. Số sai định dạng thì ném [AppFailure].
  Future<void> saveMine(String? phone);

  /// Số của những người (trong [ids]) mà mình được phép thấy: {mã người dùng: số}. Người không được thấy thì vắng mặt.
  Future<Map<String, String>> ofUsers(Iterable<String> ids);
}

class SupabasePhoneRepository implements PhoneRepository {
  SupabasePhoneRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<String?> mine() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final row = await _client.from('profile_phones').select('phone').eq('user_id', uid).maybeSingle();
      return row?['phone'] as String?;
    } on PostgrestException catch (e) {
      throw AppFailure('Không đọc được số điện thoại (${e.message})');
    }
  }

  @override
  Future<void> saveMine(String? phone) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw const AppFailure('Phiên đăng nhập đã hết hạn');
    final p = phone == null || phone.trim().isEmpty ? null : normalizePhone(phone);
    if (phone != null && phone.trim().isNotEmpty && p == null) {
      throw const AppFailure('Số điện thoại chưa đúng. Hãy nhập 8 đến 15 chữ số.');
    }
    try {
      if (p == null) {
        await _client.from('profile_phones').delete().eq('user_id', uid);
      } else {
        await _client.from('profile_phones').upsert({'user_id': uid, 'phone': p});
      }
    } on PostgrestException catch (e) {
      throw AppFailure('Không lưu được số điện thoại (${e.message})');
    }
  }

  @override
  Future<Map<String, String>> ofUsers(Iterable<String> ids) async {
    final list = ids.toSet().toList();
    if (list.isEmpty) return const {};
    try {
      final rows = await _client.from('profile_phones').select('user_id, phone').inFilter('user_id', list);
      return {for (final r in rows) r['user_id'] as String: r['phone'] as String};
    } on PostgrestException {
      return const {};
    }
  }
}

final phoneRepositoryProvider = Provider<PhoneRepository>(
  (ref) => SupabasePhoneRepository(ref.watch(supabaseClientProvider)),
);

/// Số điện thoại của chính mình (để hiện ở Hồ sơ).
final myPhoneProvider = FutureProvider.autoDispose<String?>(
  (ref) => ref.watch(phoneRepositoryProvider).mine(),
);
