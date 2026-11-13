/// Tên đường dẫn tập trung, tránh viết chuỗi rải rác.
abstract final class Routes {
  static const login = '/login';
  static const register = '/register';
  static const completeProfile = '/complete-profile';
  static const rooms = '/rooms';
  static const room = '/rooms/:id';
  static String roomPath(String id) => '/rooms/$id';
  static const measure = '/measure';
  static const ocr = '/ocr';
  static const ocrEdit = '/ocr/edit';
  static const ocrDetail = '/ocr/detail';
  static const bp = '/bp';
  static const home = '/';
  static const profile = '/profile';
  static const community = '/community';

  /// Bốn tab chính (có thanh điều hướng dưới). Màn "Sức khoẻ" dùng đường dẫn `/bp`.
  static const tabs = [home, rooms, bp, profile];

  /// Các trang không cần đăng nhập.
  static const publicRoutes = {login, register};
}
