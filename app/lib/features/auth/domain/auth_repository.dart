import 'auth_user.dart';

abstract interface class AuthRepository {
  AuthUser? get currentUser;
  Stream<AuthChange> get changes;

  Future<void> signIn({required String email, required String password});

  /// Trả về `true` nếu cần xác nhận email trước khi đăng nhập.
  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
  });

  Future<void> sendPasswordReset(String email);
  Future<void> updatePassword(String newPassword);
  Future<void> signOut();
}
