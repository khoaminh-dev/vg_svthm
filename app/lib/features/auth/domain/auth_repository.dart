import 'auth_user.dart';

abstract interface class AuthRepository {
  AuthUser? get currentUser;
  Stream<AuthChange> get changes;

  /// `true` nếu username chưa ai dùng.
  Future<bool> isUsernameAvailable(String username);

  Future<void> signIn({required String email, required String password});

  /// Trả về `true` nếu cần xác nhận email trước khi đăng nhập.
  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
    required String username,
  });

  /// Đăng nhập bằng Google. Trả về `false` nếu người dùng huỷ.
  Future<bool> signInWithGoogle();

  /// Lưu username và tên hiển thị cho tài khoản chưa có hồ sơ.
  Future<void> completeProfile({required String username, required String displayName});

  Future<void> sendPasswordReset(String email);
  Future<void> updatePassword(String newPassword);
  Future<void> signOut();
}
