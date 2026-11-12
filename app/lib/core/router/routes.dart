/// Tên đường dẫn tập trung, tránh viết chuỗi rải rác.
abstract final class Routes {
  static const login = '/login';
  static const register = '/register';
  static const completeProfile = '/complete-profile';
  static const rooms = '/rooms';
  static const room = '/rooms/:id';
  static String roomPath(String id) => '/rooms/$id';
  static const home = '/';

  /// Các trang không cần đăng nhập.
  static const publicRoutes = {login, register};
}
