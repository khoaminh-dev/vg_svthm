import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ghi lại thao tác của người dùng vào bảng `events` (web admin thống kê).
///
/// Sự kiện được gom lại và gửi theo lô (một request cho nhiều sự kiện) để giảm tải lên Supabase khi
/// có nhiều người dùng. Chạy nền, mọi lỗi đều bị nuốt để không ảnh hưởng app.
class Analytics {
  Analytics._();

  static String? currentScreen;

  /// Gửi khi đủ chừng này sự kiện hoặc sau [_flushEvery], tuỳ cái nào đến trước.
  static const _batchSize = 20;
  static const _flushEvery = Duration(seconds: 10);

  /// Giới hạn hàng đợi khi mất mạng, tránh phình bộ nhớ.
  static const _maxQueue = 200;

  static final _queue = <Map<String, Object?>>[];
  static Timer? _timer;
  static bool _flushing = false;
  static AppLifecycleListener? _lifecycle;

  /// Gọi một lần sau khi khởi tạo Supabase: tự gửi nốt hàng đợi khi app ra nền.
  static void init() {
    _lifecycle ??= AppLifecycleListener(onInactive: flush, onHide: flush, onPause: flush);
  }

  static void track(String name, [Map<String, Object?> props = const {}]) {
    try {
      if (Supabase.instance.client.auth.currentUser == null) {
        currentScreen = null; // phiên mới sẽ ghi lại màn hình đầu tiên
        return;
      }
      if (_queue.length >= _maxQueue) _queue.removeAt(0);
      _queue.add({'name': name, 'screen': currentScreen, 'props': props});
      if (_queue.length >= _batchSize) {
        flush();
      } else {
        _timer ??= Timer(_flushEvery, flush);
      }
    } catch (_) {
      // Chưa khởi tạo Supabase (test): bỏ qua.
    }
  }

  /// Gửi toàn bộ hàng đợi bằng một request. Lỗi thì đưa lại vào hàng đợi (tối đa [_maxQueue]).
  static Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_flushing || _queue.isEmpty) return;
    _flushing = true;
    final batch = List<Map<String, Object?>>.of(_queue);
    _queue.clear();
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser == null) return;
      await client.from('events').insert(batch);
    } catch (_) {
      final room = _maxQueue - _queue.length;
      if (room > 0) _queue.insertAll(0, batch.take(room));
    } finally {
      _flushing = false;
    }
  }
}

/// Tự ghi sự kiện `screen_view` mỗi khi đổi màn hình (gắn vào GoRouter.observers).
/// Chỉ tính các trang thật sự (PageRoute), bỏ qua hộp thoại / bottom sheet để không đếm trùng.
class AnalyticsObserver extends NavigatorObserver {
  void _view(Route<dynamic>? route) {
    if (route is! PageRoute) return;
    final name = route.settings.name;
    if (name == null || name.isEmpty || name == Analytics.currentScreen) return;
    Analytics.currentScreen = name;
    Analytics.track('screen_view');
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _view(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Chỉ khi đóng một trang thật mới quay về trang trước đó.
    if (route is PageRoute) _view(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _view(newRoute);
}
