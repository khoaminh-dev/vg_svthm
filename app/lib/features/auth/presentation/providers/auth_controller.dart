import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_failure.dart';
import 'auth_providers.dart';

/// Thực hiện các hành động xác thực; state là trạng thái loading/lỗi của hành động gần nhất.
class AuthController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<bool> signIn(String email, String password) =>
      _run(() => ref.read(authRepositoryProvider).signIn(email: email, password: password));

  /// Trả về `true` nếu đăng ký xong nhưng cần xác nhận email. `null` nếu lỗi.
  Future<bool?> signUp(String email, String password, String fullName, String username) async {
    bool? needsConfirm;
    final ok = await _run(() async {
      final repo = ref.read(authRepositoryProvider);
      if (!await repo.isUsernameAvailable(username)) {
        throw const AppFailure('Tên người dùng đã được sử dụng');
      }
      needsConfirm = await repo.signUp(
        email: email,
        password: password,
        fullName: fullName,
        username: username,
      );
    });
    return ok ? needsConfirm : null;
  }

  /// `true` nếu đăng nhập xong; `false` nếu huỷ hoặc lỗi (lỗi nằm trong state).
  Future<bool> signInWithGoogle() async {
    var signedIn = false;
    await _run(() async {
      signedIn = await ref.read(authRepositoryProvider).signInWithGoogle();
    });
    return signedIn;
  }

  Future<bool> completeProfile(String username, String displayName) => _run(() async {
    final repo = ref.read(authRepositoryProvider);
    if (!await repo.isUsernameAvailable(username)) {
      throw const AppFailure('Tên người dùng đã được sử dụng');
    }
    await repo.completeProfile(username: username, displayName: displayName);
  });

  Future<bool> signOut() => _run(() => ref.read(authRepositoryProvider).signOut());

  Future<bool> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(action);
    return !state.hasError;
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, void>(AuthController.new);
