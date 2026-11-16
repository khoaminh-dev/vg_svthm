import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_router.dart';
import '../../core/router/routes.dart';
import '../../core/supabase/supabase_providers.dart';
import '../auth/presentation/providers/auth_providers.dart';

/// Thông báo đẩy (FCM): xin quyền, lưu mã thiết bị cho người đang đăng nhập, bấm thông báo thì mở đúng phòng chat.
/// Chỉ chạy sau [start] (gọi từ main). Khi chưa khởi tạo Firebase (ví dụ trong test) mọi hàm đều không làm gì.
class PushService {
  PushService(this._ref);

  final Ref _ref;
  bool _started = false;
  String? _token;
  String? _pendingPath;
  StreamSubscription<String>? _refreshSub;

  Future<void> start() async {
    try {
      await Firebase.initializeApp();
      _started = true;
    } catch (_) {
      return; // thiếu cấu hình Firebase: app vẫn chạy bình thường, chỉ không có thông báo
    }
    final fm = FirebaseMessaging.instance;
    FirebaseMessaging.onMessageOpenedApp.listen(_onOpened);
    try {
      final first = await fm.getInitialMessage();
      if (first != null) _onOpened(first);
    } catch (_) {}
    _refreshSub = fm.onTokenRefresh.listen((t) {
      _token = t;
      unawaited(_save(t));
    });
    if (_ref.read(currentUserProvider) != null) unawaited(register());
  }

  /// Xin quyền và lưu mã thiết bị cho người đang đăng nhập. Gọi mỗi lần đăng nhập.
  Future<void> register() async {
    if (!_started) return;
    try {
      final fm = FirebaseMessaging.instance;
      final settings = await fm.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final t = await fm.getToken();
      if (t == null) return;
      _token = t;
      await _save(t);
    } catch (_) {}
    _flushPending();
  }

  Future<void> _save(String token) async {
    try {
      if (_ref.read(currentUserProvider) == null) return;
      await _ref
          .read(supabaseClientProvider)
          .rpc(
            'register_device',
            params: {'p_token': token, 'p_platform': 'android'},
          );
    } catch (_) {}
  }

  /// Gỡ mã thiết bị khỏi tài khoản hiện tại (gọi TRƯỚC khi đăng xuất, để người khác dùng chung máy không nhận tin của mình).
  Future<void> unregister() async {
    final t = _token;
    if (!_started || t == null) return;
    try {
      await _ref
          .read(supabaseClientProvider)
          .rpc('unregister_device', params: {'p_token': t});
    } catch (_) {}
  }

  void _onOpened(RemoteMessage m) {
    // Thông báo cập nhật: mở app là đủ, hộp thoại cập nhật tự hiện.
    final path = pathFor(m.data);
    if (path == null) return;
    _pendingPath = path;
    if (_ref.read(currentUserProvider) != null) _flushPending();
  }

  void _flushPending() {
    final path = _pendingPath;
    if (path == null || _ref.read(currentUserProvider) == null) return;
    _pendingPath = null;
    // Chờ router dựng xong trang chủ rồi mới đẩy màn đích lên trên.
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      _ref.read(routerProvider).push(path);
    });
  }

  /// Màn cần mở khi bấm một thông báo (theo `data` của FCM), hoặc null nếu chỉ cần mở app.
  static String? pathFor(Map<String, dynamic> data) {
    final id = data['room_id'];
    final owner = data['owner_id'];
    switch (data['type']) {
      case 'message':
        return id is String && id.isNotEmpty ? Routes.roomPath(id) : null;
      case 'family_alert':
        return owner is String && owner.isNotEmpty
            ? Routes.familyPersonPath(owner)
            : null;
      case 'nudge':
        return Routes.measure;
      default:
        return null;
    }
  }

  void dispose() => _refreshSub?.cancel();
}

final pushServiceProvider = Provider<PushService>((ref) {
  final s = PushService(ref);
  // Đăng nhập (hoặc mở app khi đã đăng nhập) thì lưu mã thiết bị.
  ref.listen(currentUserProvider, (prev, next) {
    if (next != null && prev?.id != next.id) unawaited(s.register());
  });
  ref.onDispose(s.dispose);
  return s;
});

/// Cài đặt thông báo của người dùng (bảng `push_prefs`; chưa có dòng thì dùng mặc định).
class PushPrefs {
  const PushPrefs({
    this.messages = true,
    this.updates = true,
    this.showText = false,
  });

  final bool messages;
  final bool updates;
  final bool showText;

  PushPrefs copyWith({bool? messages, bool? updates, bool? showText}) =>
      PushPrefs(
        messages: messages ?? this.messages,
        updates: updates ?? this.updates,
        showText: showText ?? this.showText,
      );
}

class PushPrefsNotifier extends AsyncNotifier<PushPrefs> {
  @override
  Future<PushPrefs> build() async {
    try {
      final uid = ref.watch(currentUserProvider.select((u) => u?.id));
      if (uid == null) return const PushPrefs();
      final row = await ref
          .read(supabaseClientProvider)
          .from('push_prefs')
          .select('messages, updates, show_text')
          .eq('user_id', uid)
          .maybeSingle();
      if (row == null) return const PushPrefs();
      return PushPrefs(
        messages: row['messages'] as bool? ?? true,
        updates: row['updates'] as bool? ?? true,
        showText: row['show_text'] as bool? ?? false,
      );
    } catch (_) {
      return const PushPrefs();
    }
  }

  Future<void> save(PushPrefs next) async {
    final before = state;
    state = AsyncData(next);
    try {
      final uid = ref.read(currentUserProvider)?.id;
      if (uid == null) return;
      await ref.read(supabaseClientProvider).from('push_prefs').upsert({
        'user_id': uid,
        'messages': next.messages,
        'updates': next.updates,
        'show_text': next.showText,
      });
    } catch (_) {
      state = before; // không lưu được thì trả công tắc về như cũ
    }
  }
}

final pushPrefsProvider = AsyncNotifierProvider<PushPrefsNotifier, PushPrefs>(
  PushPrefsNotifier.new,
);
