import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';

/// Cờ bật/tắt tính năng Camera (bảng `app_flags`, khoá `camera`, mặc định tắt). Lỗi mạng thì coi như tắt, nhưng
/// không nhớ kết quả lỗi mãi: provider tự huỷ khi không còn màn nào xem nên lần sau sẽ hỏi lại.
final cameraEnabledProvider = FutureProvider.autoDispose<bool>((ref) async {
  try {
    final row = await ref
        .watch(supabaseClientProvider)
        .from('app_flags')
        .select('enabled')
        .eq('key', 'camera')
        .maybeSingle();
    return row?['enabled'] == true;
  } catch (_) {
    return false;
  }
});
