/// Lỗi nghiệp vụ đã được chuyển thành thông báo thân thiện để hiển thị cho người dùng.
class AppFailure implements Exception {
  const AppFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Lấy thông báo hiển thị từ một lỗi bất kỳ.
String errorMessage(Object error) =>
    error is AppFailure ? error.message : 'Đã có lỗi xảy ra, vui lòng thử lại';
