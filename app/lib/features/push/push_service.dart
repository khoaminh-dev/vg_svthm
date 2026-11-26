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
    // Đang mở app: cảnh báo khẩn cấp DEMO tự bật màn đỏ (tin khác vẫn chỉ hiện ở khay thông báo như trước).
    FirebaseMessaging.onMessage.listen((m) {
      if (m.data['type'] == 'demo_alert') _onOpened(m);
    });
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
      case 'sos':
        final sos = data['sos_id'];
        return sos is String && sos.isNotEmpty ? Routes.sosFor(sos) : null;
      case 'demo_alert':
        final alert = data['alert_id'];
        return alert is String && alert.isNotEmpty ? Routes.demoAlertFor(alert) : null;
      case 'meds':
        return Routes.bp;
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
    this.familyAlerts = true,
    this.doseAlerts = true,
    this.digest = false,
    this.quietStart,
    this.quietEnd,
  });

  final bool messages;
  final bool updates;
  final bool showText;

  /// Cảnh báo về người thân (huyết áp cao, liên kết...).
  final bool familyAlerts;

  /// Báo khi người thân quên thuốc, sắp hết thuốc, sắp tái khám.
  final bool doseAlerts;

  /// Tóm tắt cuối ngày về người thân.
  final bool digest;

  /// Giờ yên tĩnh "HH:MM" (áp cho thông báo thường, không áp cho SOS và huyết áp rất cao).
  final String? quietStart;
  final String? quietEnd;

  bool get hasQuiet => quietStart != null && quietEnd != null;

  PushPrefs copyWith({
    bool? messages,
    bool? updates,
    bool? showText,
    bool? familyAlerts,
    bool? doseAlerts,
    bool? digest,
    ({String? start, String? end})? quiet,
  }) => PushPrefs(
    messages: messages ?? this.messages,
    updates: updates ?? this.updates,
    showText: showText ?? this.showText,
    familyAlerts: familyAlerts ?? this.familyAlerts,
    doseAlerts: doseAlerts ?? this.doseAlerts,
    digest: digest ?? this.digest,
    quietStart: quiet != null ? quiet.start : quietStart,
    quietEnd: quiet != null ? quiet.end : quietEnd,
  );
}

/// "22:00:00" -> "22:00".
String? _hm(Object? v) {
  if (v is! String || v.length < 5) return null;
  return v.substring(0, 5);
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
          .select('messages, updates, show_text, family_alerts, dose_alerts, digest, quiet_start, quiet_end')
          .eq('user_id', uid)
          .maybeSingle();
      if (row == null) return const PushPrefs();
      return PushPrefs(
        messages: row['messages'] as bool? ?? true,
        updates: row['updates'] as bool? ?? true,
        showText: row['show_text'] as bool? ?? false,
        familyAlerts: row['family_alerts'] as bool? ?? true,
        doseAlerts: row['dose_alerts'] as bool? ?? true,
        digest: row['digest'] as bool? ?? false,
        quietStart: _hm(row['quiet_start']),
        quietEnd: _hm(row['quiet_end']),
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
        'family_alerts': next.familyAlerts,
        'dose_alerts': next.doseAlerts,
        'digest': next.digest,
        'quiet_start': next.quietStart,
        'quiet_end': next.quietEnd,
      });
    } catch (_) {
      state = before; // không lưu được thì trả công tắc về như cũ
    }
  }
}

final pushPrefsProvider = AsyncNotifierProvider<PushPrefsNotifier, PushPrefs>(
  PushPrefsNotifier.new,
);
