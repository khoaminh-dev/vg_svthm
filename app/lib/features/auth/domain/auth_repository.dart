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
    AppRole? role,
    bool forParent = false,
  });

  /// Chọn hoặc đổi vai trò. [forParent]: cài hộ cho cha mẹ (kèm một lần dẫn tới màn mời người thân).
  Future<void> setRole(AppRole role, {bool forParent = false});

  /// Đã dẫn người dùng tới màn mời người thân, không dẫn lại nữa.
  Future<void> clearInstallGuide();

  /// Đăng nhập bằng Google. Trả về `false` nếu người dùng huỷ.
  Future<bool> signInWithGoogle();

  /// Lưu username và tên hiển thị cho tài khoản chưa có hồ sơ.
  Future<void> completeProfile({
    required String username,
    required String displayName,
  });

  Future<void> signOut();
}
