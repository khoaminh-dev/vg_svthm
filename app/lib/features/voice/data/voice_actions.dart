import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/router/app_router.dart';
import '../../../core/router/routes.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../bp/domain/bp_models.dart';
import '../../bp/presentation/providers/bp_providers.dart';
import '../../chat/domain/room.dart';
import '../../chat/presentation/providers/chat_providers.dart';
import '../../entertainment/data/youtube_service.dart';
import '../../entertainment/presentation/entertainment_providers.dart';
import '../domain/voice_models.dart';

/// Bộ thực thi lệnh Vy dùng chung cho Vy thường (`VoiceController`) và Vy Live (`LiveLabController`).
/// Một nơi duy nhất biết cách "mở màn nào, phát video, gửi tin, đọc huyết áp" để hai đường không lệch nhau.
/// Khi thêm hoặc đổi hành động, cập nhật cả `docs/APP_MAP.md` mục 3.
class VoiceActions {
  VoiceActions(this._ref);

  final Ref _ref;

  Map<String, List<String>> _aliases = {};

  /// Lệnh đổi màn hình: chạy xong thì Vy thường thu gọn màn Vy để người dùng thấy kết quả.
  static const navIntents = {
    'send_message',
    'open_chat',
    'open_feature',
    'measure_bp',
    'play_video',
    'video_control',
    'show_bp',
    'go_home',
    'go_back',
  };

  /// Cách xưng hô đã lưu của người dùng (mặc định "bác").
  Future<String> loadHonorific() async {
    try {
      final c = _ref.read(supabaseClientProvider);
      final uid = c.auth.currentUser?.id;
      if (uid == null) return 'bác';
      final p = await c
          .from('voice_prefs')
          .select('honorific')
          .eq('user_id', uid)
          .maybeSingle();
      return (p?['honorific'] as String?) ?? 'bác';
    } catch (_) {
      return 'bác';
    }
  }

  /// Danh bạ (các phòng chat) kèm bí danh đã học, gửi lên máy chủ để phân giải người nhận.
  Future<List<VoiceContact>> contacts() async {
    try {
      final c = _ref.read(supabaseClientProvider);
      final uid = c.auth.currentUser?.id;
      final rooms = await _ref.read(roomsProvider.future);
      try {
        final rows = await c
            .from('voice_aliases')
            .select('alias_norm, contact_id')
            .eq('user_id', uid ?? '');
        final m = <String, List<String>>{};
        for (final r in rows) {
          (m[r['contact_id'] as String] ??= []).add(r['alias_norm'] as String);
        }
        _aliases = m;
      } catch (_) {}
      return [
        for (final r in rooms)
          VoiceContact(
            id: r.id,
            kind: r.isDirect ? 'direct' : 'group',
            name: r.displayName,
            username: r.peer?.username,
            aliases: _aliases[r.id] ?? const [],
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  String? currentRoomId() {
    final path = currentPath(_ref.read(routerProvider));
    final m = RegExp(r'^/rooms/([^/]+)$').firstMatch(path);
    return m?.group(1);
  }

  String screenName() => currentPath(_ref.read(routerProvider));

  /// Chạy lệnh trên app. Trả về câu nói thay thế (khi cần báo kết quả/lỗi), hoặc null để dùng câu của server.
  Future<String?> execute(
    VoiceTask t,
    List<VoiceContact> contacts,
    String honorific,
  ) async {
    final router = _ref.read(routerProvider);
    final s = t.slots;
    switch (t.intent) {
      case 'send_message':
        final roomId = s['room_id'];
        final content = s['content'];
        if (roomId == null || content == null)
          return 'Con chưa gửi được, $honorific thử lại nhé.';
        final ok = await _ref
            .read(chatRepositoryProvider)
            .sendMessage(roomId, content)
            .then((_) => true)
            .catchError((_) => false);
        Analytics.track('voice_send_message', {'ok': ok});
        if (!ok)
          return 'Con gửi chưa được, $honorific kiểm tra mạng rồi thử lại nhé.';
        _openRoom(roomId);
        return null;
      case 'open_chat':
        final id = s['room_id'];
        if (id == null) return null;
        _openRoom(id);
        return null;
      case 'open_feature':
        switch (s['feature']) {
          case 'chat':
            router.go(Routes.rooms);
          case 'ocr':
            router.go(Routes.measure);
          case 'bp':
            router.go(Routes.bp);
          case 'fun':
            router.go(Routes.entertainment);
          default:
            router.go(Routes.home);
        }
        return null;
      case 'play_video':
        return await _playVideo(s['content'], router, honorific);
      case 'video_control':
        return _controlVideo(s['content'], honorific);
      case 'measure_bp':
        router.go(Routes.measure);
        return 'Dạ, $honorific chụp màn hình máy đo huyết áp giúp con nhé.';
      case 'show_bp':
        router.go(Routes.bp);
        return null;
      case 'read_bp':
        return await readBp(honorific);
      case 'go_home':
        router.go(Routes.home);
        return null;
      case 'go_back':
        if (router.canPop()) {
          router.pop();
        } else {
          router.go(Routes.home);
        }
        return null;
    }
    return null;
  }

  /// Tìm video theo lời nói: từ khoá cụ thể thì phát kết quả đầu tiên, chung chung thì hiện danh sách để chọn.
  Future<String?> _playVideo(
    String? query,
    GoRouter router,
    String honorific,
  ) async {
    final q = query?.trim() ?? '';
    if (q.isEmpty) return null;
    Analytics.track('voice_play_video', {'len': q.length});
    final List<VideoItem> found;
    try {
      found = await _ref.read(videoSearchProvider).search(q, limit: 10);
    } catch (_) {
      return 'Con tìm video chưa được, $honorific kiểm tra mạng rồi thử lại nhé.';
    }
    if (found.isEmpty) return 'Con không tìm thấy video nào về "$q" ạ.';
    _ref.read(videoQueryProvider.notifier).set(q);
    router.go(Routes.entertainment);
    if (isVagueVideoQuery(q)) {
      return 'Dạ, con tìm được mấy video rồi, $honorific chọn một video nhé.';
    }
    final first = found.first;
    _ref.read(videoQueueProvider.notifier).set(found);
    router.push(Routes.player, extra: first);
    final title = first.title.length > 70
        ? '${first.title.substring(0, 70)}…'
        : first.title;
    return 'Dạ, con mở $title ạ.';
  }

  /// Điều khiển video đang phát bằng giọng nói.
  String? _controlVideo(String? action, String honorific) {
    if (!_ref.read(playerOpenProvider))
      return 'Dạ, hiện chưa có video nào đang phát ạ.';
    final a = switch (action?.toLowerCase()) {
      'pause' => PlayerAction.pause,
      'play' => PlayerAction.play,
      'next' => PlayerAction.next,
      'previous' => PlayerAction.previous,
      'louder' => PlayerAction.louder,
      'quieter' => PlayerAction.quieter,
      _ => null,
    };
    if (a == null) return null;
    _ref.read(playerCommandProvider.notifier).send(a);
    Analytics.track('voice_video_control', {'action': action});
    return switch (a) {
      PlayerAction.pause => 'Dạ, con dừng rồi ạ.',
      PlayerAction.play => 'Dạ, con phát tiếp ạ.',
      PlayerAction.next => 'Dạ, con chuyển bài ạ.',
      PlayerAction.previous => 'Dạ, con mở lại bài trước ạ.',
      PlayerAction.louder =>
        'Dạ, con tăng âm lượng rồi ạ. Nếu chưa đủ to, $honorific bấm nút to bên hông máy giúp con nhé.',
      PlayerAction.quieter => 'Dạ, con giảm âm lượng rồi ạ.',
    };
  }

  void _openRoom(String id) {
    final router = _ref.read(routerProvider);
    final rooms = _ref.read(roomsProvider).value;
    Room? room;
    if (rooms != null) {
      for (final r in rooms) {
        if (r.id == id) room = r;
      }
    }
    // Đã ở đúng phòng thì không mở chồng lên.
    if (currentRoomId() == id) return;
    router.go(Routes.rooms);
    router.push(Routes.roomPath(id), extra: room);
  }

  Future<String> readBp(String honorific) async {
    try {
      final list = await _ref.read(bpReadingsProvider.future);
      if (list.isEmpty)
        return 'Chưa có kết quả đo nào. ${honorific[0].toUpperCase()}${honorific.substring(1)} đo huyết áp rồi chụp lại giúp con nhé.';
      final r = list.reduce(
        (a, b) => a.measuredAt.isAfter(b.measuredAt) ? a : b,
      );
      final cat = BpCategory.of(r.systolic, r.diastolic).label;
      final pulse = r.pulse == null ? '' : ', mạch ${r.pulse}';
      return 'Lần đo gần nhất: huyết áp ${r.systolic} trên ${r.diastolic}$pulse. Mức: $cat.';
    } catch (_) {
      return 'Con chưa đọc được kết quả, $honorific thử lại sau nhé.';
    }
  }
}

final voiceActionsProvider = Provider<VoiceActions>(VoiceActions.new);
