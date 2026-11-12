/// Người dùng đã đăng nhập (không phụ thuộc Supabase).
class AuthUser {
  const AuthUser({required this.id, this.email, this.fullName});

  final String id;
  final String? email;
  final String? fullName;

  String get displayName =>
      (fullName?.trim().isNotEmpty ?? false) ? fullName! : (email ?? 'Người dùng');
}

/// Một thay đổi trạng thái xác thực.
class AuthChange {
  const AuthChange({this.user, this.passwordRecovery = false});

  final AuthUser? user;

  /// `true` khi người dùng vừa mở link đặt lại mật khẩu từ email.
  final bool passwordRecovery;
}
