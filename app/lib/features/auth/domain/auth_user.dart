/// Vai trò quyết định bộ khung giao diện: người cao tuổi hoặc người thân (chăm sóc).
enum AppRole {
  elder('elder', 'Người cao tuổi'),
  family('family', 'Người thân');

  const AppRole(this.code, this.label);

  final String code;
  final String label;

  static AppRole? of(Object? code) {
    for (final r in values) {
      if (r.code == code) return r;
    }
    return null;
  }
}

/// Người dùng đã đăng nhập (không phụ thuộc Supabase).
class AuthUser {
  const AuthUser({
    required this.id,
    this.email,
    this.fullName,
    this.username,
    this.avatarUrl,
    this.role,
    this.installForParent = false,
  });

  final String id;
  final String? email;
  final String? fullName;
  final String? username;
  final String? avatarUrl;

  /// Chưa chọn vai trò (tài khoản cũ hoặc đăng nhập Google lần đầu): app hỏi "Bạn là ai?".
  final AppRole? role;

  /// Đăng ký bằng lựa chọn "cài hộ cho cha mẹ": sau khi vào app, đưa tới màn mời người thân một lần.
  final bool installForParent;

  /// Chưa chọn tên người dùng (thường là tài khoản Google mới).
  bool get needsProfile => username == null || username!.isEmpty;

  String get displayName => (fullName?.trim().isNotEmpty ?? false)
      ? fullName!
      : (email ?? 'Người dùng');
}

/// Một thay đổi trạng thái xác thực.
class AuthChange {
  const AuthChange({this.user});

  final AuthUser? user;
}
