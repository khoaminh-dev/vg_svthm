/// Hàm kiểm tra dữ liệu form. Trả về `null` nếu hợp lệ, ngược lại là thông báo lỗi.
abstract final class Validators {
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? required(String? v, {String field = 'Trường này'}) =>
      (v == null || v.trim().isEmpty) ? '$field không được để trống' : null;

  static String? email(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'Vui lòng nhập email';
    if (!_email.hasMatch(value)) return 'Email không hợp lệ';
    return null;
  }

  static final _username = RegExp(r'^[a-z0-9_]{3,20}$');

  static String? username(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'Vui lòng nhập tên người dùng';
    if (!_username.hasMatch(value)) {
      return 'Dùng 3-20 ký tự: chữ thường, số hoặc dấu gạch dưới';
    }
    return null;
  }

  static String? password(String? v) {
    final value = v ?? '';
    if (value.isEmpty) return 'Vui lòng nhập mật khẩu';
    if (value.length < 8) return 'Mật khẩu tối thiểu 8 ký tự';
    return null;
  }

  static String? Function(String?) confirmPassword(String Function() original) =>
      (v) {
        if (v == null || v.isEmpty) return 'Vui lòng nhập lại mật khẩu';
        if (v != original()) return 'Mật khẩu nhập lại không khớp';
        return null;
      };
}
