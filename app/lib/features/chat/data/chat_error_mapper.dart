import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';

AppFailure mapChatError(Object error) {
  if (error is AppFailure) return error;
  if (error is PostgrestException) {
    switch (error.code) {
      case 'P0002':
        return const AppFailure('Không tìm thấy người dùng này');
      case '42501':
        return const AppFailure('Bạn không có quyền thực hiện thao tác này');
      case '22023':
        return const AppFailure('Không thể thực hiện với phòng hoặc người dùng này');
      case '23514':
        return const AppFailure('Nội dung không hợp lệ (quá dài hoặc để trống)');
      case 'P0001':
        if (error.message.contains('image_limit')) {
          return const AppFailure('Hôm nay bạn đã gửi nhiều ảnh rồi, ngày mai gửi tiếp nhé');
        }
    }
    return AppFailure(error.message);
  }
  if (error is StorageException) {
    final code = error.statusCode;
    if (code == '413') return const AppFailure('Ảnh quá lớn (tối đa 5 MB)');
    if (code == '400' || code == '403' || code == '415') {
      return const AppFailure('Không gửi được ảnh này, hãy thử ảnh khác');
    }
    return const AppFailure('Gửi ảnh chưa được, hãy kiểm tra mạng rồi thử lại');
  }
  return const AppFailure('Không kết nối được máy chủ, hãy kiểm tra mạng');
}
