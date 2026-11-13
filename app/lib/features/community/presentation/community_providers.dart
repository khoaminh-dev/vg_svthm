import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../../shared/models/profile.dart';

/// Cờ bật/tắt màn Cộng đồng (bảng `app_flags`, khoá `community`). Lỗi mạng thì coi như tắt.
final communityEnabledProvider = FutureProvider<bool>((ref) async {
  try {
    final row = await ref
        .watch(supabaseClientProvider)
        .from('app_flags')
        .select('enabled')
        .eq('key', 'community')
        .maybeSingle();
    return row?['enabled'] == true;
  } catch (_) {
    return false;
  }
});

/// Từ khoá tìm kiếm trong màn Cộng đồng.
class CommunityQuery extends Notifier<String> {
  @override
  String build() => '';
  void set(String v) => state = v.trim();
}

final communityQueryProvider = NotifierProvider<CommunityQuery, String>(CommunityQuery.new);

/// Danh sách người dùng (trừ mình), lọc theo từ khoá.
final communityUsersProvider = FutureProvider.autoDispose<List<Profile>>((ref) async {
  final q = ref.watch(communityQueryProvider);
  final rows = await ref
      .watch(supabaseClientProvider)
      .rpc('community_users', params: {'p_query': q, 'p_limit': 100}) as List;
  return rows.map((m) => Profile.fromMap(Map<String, dynamic>.from(m as Map))).toList();
});
