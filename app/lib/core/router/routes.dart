/// Tên đường dẫn tập trung, tránh viết chuỗi rải rác.
abstract final class Routes {
  static const login = '/login';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
  static const resetPassword = '/reset-password';
  static const home = '/';

  /// Các trang không cần đăng nhập.
  static const publicRoutes = {login, register, forgotPassword};
}
