import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ghi lại thao tác của người dùng vào bảng `events` (web admin thống kê).
/// Chạy nền, mọi lỗi đều bị nuốt để không ảnh hưởng app.
class Analytics {
  Analytics._();

  static String? currentScreen;

  static void track(String name, [Map<String, Object?> props = const {}]) {
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser == null) return;
      client
          .from('events')
          .insert({'name': name, 'screen': currentScreen, 'props': props})
          .then((_) {}, onError: (_) {});
    } catch (_) {
      // Chưa khởi tạo Supabase (test) hoặc lỗi mạng: bỏ qua.
    }
  }
}

/// Tự ghi sự kiện `screen_view` mỗi khi đổi màn hình (gắn vào GoRouter.observers).
class AnalyticsObserver extends NavigatorObserver {
  void _view(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null || name.isEmpty) return;
    Analytics.currentScreen = name;
    Analytics.track('screen_view');
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _view(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _view(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _view(newRoute);
}
