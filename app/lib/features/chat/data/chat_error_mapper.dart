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
      case '23514':
        return const AppFailure('Nội dung không hợp lệ (quá dài hoặc để trống)');
    }
    return AppFailure(error.message);
  }
  return const AppFailure('Không kết nối được máy chủ, hãy kiểm tra mạng');
}
