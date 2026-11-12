import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../data/supabase_auth_repository.dart';
import '../../domain/auth_repository.dart';
import '../../domain/auth_user.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(ref.watch(supabaseClientProvider)),
);

/// Luồng thay đổi trạng thái đăng nhập.
final authChangesProvider = StreamProvider<AuthChange>(
  (ref) => ref.watch(authRepositoryProvider).changes,
);

/// Người dùng hiện tại (null nếu chưa đăng nhập).
final currentUserProvider = Provider<AuthUser?>((ref) {
  ref.watch(authChangesProvider);
  return ref.watch(authRepositoryProvider).currentUser;
});
