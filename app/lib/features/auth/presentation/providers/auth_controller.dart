import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_providers.dart';

/// Thực hiện các hành động xác thực; state là trạng thái loading/lỗi của hành động gần nhất.
class AuthController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<bool> signIn(String email, String password) => _run(
        () => ref.read(authRepositoryProvider).signIn(email: email, password: password),
      );

  /// Trả về `true` nếu đăng ký xong nhưng cần xác nhận email. `null` nếu lỗi.
  Future<bool?> signUp(String email, String password, String fullName) async {
    bool? needsConfirm;
    final ok = await _run(() async {
      needsConfirm = await ref.read(authRepositoryProvider).signUp(
            email: email,
            password: password,
            fullName: fullName,
          );
    });
    return ok ? needsConfirm : null;
  }

  Future<bool> sendPasswordReset(String email) =>
      _run(() => ref.read(authRepositoryProvider).sendPasswordReset(email));

  Future<bool> updatePassword(String password) => _run(() async {
        await ref.read(authRepositoryProvider).updatePassword(password);
        ref.read(passwordRecoveryProvider.notifier).set(false);
      });

  Future<bool> signOut() => _run(() async {
        await ref.read(authRepositoryProvider).signOut();
        ref.read(passwordRecoveryProvider.notifier).set(false);
      });

  Future<bool> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(action);
    return !state.hasError;
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, void>(AuthController.new);
