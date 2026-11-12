import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';

/// Chuyển lỗi Supabase thành thông báo tiếng Việt.
AppFailure mapAuthError(Object error) {
  if (error is AuthException) {
    final code = error.code ?? '';
    final msg = error.message.toLowerCase();

    if (code == 'invalid_credentials' || msg.contains('invalid login')) {
      return const AppFailure('Email hoặc mật khẩu không đúng');
    }
    if (code == 'email_not_confirmed' || msg.contains('not confirmed')) {
      return const AppFailure('Email chưa được xác nhận, hãy kiểm tra hộp thư');
    }
    if (code == 'user_already_exists' || msg.contains('already registered')) {
      return const AppFailure('Email này đã được đăng ký');
    }
    if (code == 'weak_password' || msg.contains('password should')) {
      return const AppFailure('Mật khẩu quá yếu, hãy dùng ít nhất 8 ký tự');
    }
    if (code == 'over_email_send_rate_limit' || error.statusCode == '429') {
      return const AppFailure('Thao tác quá nhanh, vui lòng thử lại sau ít phút');
    }
    if (code == 'same_password') {
      return const AppFailure('Mật khẩu mới phải khác mật khẩu cũ');
    }
    return AppFailure(error.message);
  }
  if (error is PostgrestException && error.code == '23505') {
    return const AppFailure('Tên người dùng đã được sử dụng');
  }
  return const AppFailure('Không kết nối được máy chủ, hãy kiểm tra mạng');
}
