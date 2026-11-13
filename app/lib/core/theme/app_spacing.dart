/// Khoảng cách và bo góc dùng thống nhất toàn app.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;

  static const double radius = 12;

  /// Thẻ và ô lớn.
  static const double radiusLg = 20;

  /// Tấm lớn, hộp thoại.
  static const double radiusXl = 28;

  /// Nút, chip, thanh điều hướng dạng viên thuốc.
  static const double radiusPill = 999;

  /// Vùng chạm tối thiểu cho người lớn tuổi (lớn hơn mức 48 của Material).
  static const double tapTarget = 56;

  static const double maxFormWidth = 420;
}
