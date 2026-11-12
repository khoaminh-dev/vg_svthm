/// Cấu hình môi trường, truyền khi chạy bằng `--dart-define`.
///
/// flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
/// Hoặc dùng `--dart-define-from-file=env.json`.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Web client ID của Google (dùng làm serverClientId, Supabase kiểm tra token bằng ID này).
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Deep link mà email xác nhận đăng ký sẽ mở lại app.
  static const authCallbackRedirect = 'viegrand://auth-callback';

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
