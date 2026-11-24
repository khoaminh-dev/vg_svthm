import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/router/app_router.dart';
import '../../../core/router/routes.dart';
import '../../../core/supabase/supabase_providers.dart';
import 'package:flutter/material.dart' show Color;

import '../../../core/theme/app_theme.dart';
import '../../bp/domain/bp_models.dart';
import '../../bp/presentation/providers/bp_providers.dart';
import '../../chat/domain/room.dart';
import '../../chat/presentation/providers/chat_providers.dart';
import '../core/vy_settings.dart';
import '../../entertainment/data/media_memory.dart';
import '../../entertainment/data/shared_video.dart';
import '../../entertainment/data/video_rank.dart';
import '../../entertainment/data/youtube_service.dart';
import '../../entertainment/presentation/entertainment_providers.dart';
import '../../health/presentation/providers/health_providers.dart';
import '../../meds/domain/meds_models.dart';
import '../../meds/presentation/meds_providers.dart';
import '../core/vy_card.dart';
import '../core/vi_text.dart';
import '../core/vy_core.dart';
import '../../safety/presentation/sos_screen.dart' show sosFailedId;
import 'direct_caller.dart';
import '../core/vy_cursor.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../family/presentation/family_providers.dart';
import '../../profile/data/phone_repository.dart';
import '../../safety/domain/safety_models.dart' show CardContact, EmergencyCard, dialable;
import '../../safety/presentation/safety_providers.dart';
import '../core/control_registry.dart';
import '../domain/voice_models.dart';

/// Bộ thực thi lệnh Vy dùng chung cho Vy thường (`VoiceController`) và Vy Live (`LiveLabController`).
/// Một nơi duy nhất biết cách "mở màn nào, phát video, gửi tin, đọc huyết áp" để hai đường không lệch nhau.
/// Khi thêm hoặc đổi hành động, cập nhật cả `docs/APP_MAP.md` mục 3.
class VoiceActions {
  VoiceActions(this._ref);

  final Ref _ref;

  Map<String, List<String>> _aliases = {};

  /// Tin đã đủ người (khớp danh bạ) và nội dung: tự gửi theo đếm ngược, không hỏi xác nhận.
  static bool canAutoSend(VoiceTask? t) =>
      t != null &&
      t.intent == 'send_message' &&
      (t.slots['room_id'] ?? '').isNotEmpty &&
      (t.slots['content'] ?? '').trim().isNotEmpty;

  // Chặn gửi trùng một tin (cùng người, cùng nội dung) trong 2 phút, kể cả khi bấm "Gửi ngay" rồi hết giờ đếm ngược.
  final Map<String, DateTime> _recentSends = {};

  /// Tin gửi bằng giọng: hiện thẻ có TÊN người nhận thật to + nội dung, đếm ngược rồi TỰ GỬI (người dùng muốn không phải bấm xác nhận).
  /// Huỷ hoặc đóng Vy trước khi hết giờ thì KHÔNG gửi. Tên khớp gần giống thì đếm lâu hơn và có dòng nhắc. Trả câu Vy nói.
  String startSend(VoiceTask t, String honorific) {
    final s = t.slots;
    final name = s['recipient_name'] ?? 'người nhận';
    final text = (s['content'] ?? '').trim();
    final fuzzy = (s['recipient_fuzzy'] ?? '').isNotEmpty;
    final seconds = fuzzy ? 6 : 4;
    final fp = '${s['room_id']}|$text';
    var fired = false;
    final notifier = _ref.read(vyCardProvider.notifier);
    void fire() {
      if (fired) return;
      fired = true;
      final last = _recentSends[fp];
      if (last != null && DateTime.now().difference(last) < const Duration(minutes: 2)) {
        notifier.show(NoticeCard(title: 'Tin này vừa gửi rồi', body: 'Con không gửi lại lần nữa ạ.'));
        return;
      }
      _recentSends[fp] = DateTime.now();
      Analytics.track('voice_send_auto', {'fuzzy': fuzzy});
      unawaited(() async {
        final out = await execute(t, const [], honorific);
        if (out != null) notifier.show(NoticeCard(title: 'Chưa gửi được', body: out));
      }());
    }

    notifier.show(
      SendCard(
        name: name,
        text: text,
        seconds: seconds,
        fuzzy: fuzzy,
        onSend: fire,
        actions: [
          VyCardAction(label: 'Gửi ngay', primary: true, run: fire),
          VyCardAction(label: 'Huỷ', run: () {
            fired = true; // đã huỷ: bộ đếm có chạy tiếp cũng không gửi
            notifier.clear();
          }),
        ],
      ),
    );
    final lead = fuzzy ? 'Con nghe gần giống tên $name. ' : '';
    return 'Dạ, ${lead}con gửi cho $name: $text. ${_cap(honorific)} bấm Huỷ nếu không muốn gửi ạ.';
  }

  /// Lệnh đổi màn hình: chạy xong thì Vy thường thu gọn màn Vy để người dùng thấy kết quả.
  static const navIntents = {
    'scroll',
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
        // Thẻ "Đã gửi" hiện ngay tại màn đang đứng (không nhảy sang phòng chat).
        _ref.read(vyCardProvider.notifier).show(
          SentCard(
            to: s['recipient_name'] ?? 'người nhận',
            text: content,
            actions: [
              VyCardAction(label: 'Mở cuộc trò chuyện', run: () => _openRoom(roomId)),
            ],
          ),
        );
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
      case 'read_meds':
        return await readMeds(honorific, forgot: (s['content'] ?? '').toLowerCase() == 'forgot');
      case 'mark_dose':
        return await markDoseTaken(honorific);
      case 'snooze_dose':
        return await snoozeDose(honorific);
      case 'record_bp':
        return await recordBp(s, honorific);
      case 'read_messages':
        return await readMessages(honorific);
      case 'sos_start':
        return startSos(honorific);
      case 'call_contact':
        return await callContact(s['recipient_text'] ?? '', honorific);
      case 'scroll':
        return _scroll(s['content'], honorific);
      case 'read_list':
        return _readList(honorific);
      case 'go_home':
        router.go(Routes.home);
        return null;
      case 'invoke_control':
        // Bấm một điều khiển theo mã (đã được máy chủ kiểm tra có trong ngữ cảnh). App kiểm tra lại mức: mức 3 không bấm.
        final id = s['control_id'];
        if (id == null) return null;
        final set = s['set'];
        // Kiểm tra trước; được thì để con trỏ bay tới rồi bấm (không chờ: Vy nói câu của nút ngay lúc con trỏ khởi hành).
        final cursor = _ref.read(vyCursorProvider);
        final r = cursor.check(id);
        Analytics.track('voice_invoke_control', {'id': id, 'result': r.name});
        if (r == VyInvokeResult.done) {
          unawaited(cursor.press(id, set: set == null ? null : set == '1'));
        }
        return switch (r) {
          VyInvokeResult.done => null,
          VyInvokeResult.notFound => 'Con chưa thấy nút đó trên màn hình ạ.',
          VyInvokeResult.disabled => 'Dạ, nút này bây giờ chưa bấm được ạ.',
          VyInvokeResult.selfOnly => '${honorific[0].toUpperCase()}${honorific.substring(1)} tự bấm nút này giúp con nhé.',
        };
      case 'point_control':
        // Việc người dùng phải tự bấm (mức 3): con trỏ chỉ vào nút, tuyệt đối không bấm.
        final target = s['target_id'];
        if (target != null) unawaited(_ref.read(vyCursorProvider).point(target));
        return null;
      case 'choose_item':
        final n = int.tryParse(s['n'] ?? '');
        final listId = s['list_id'];
        if (n == null || listId == null) return null;
        final ok = _ref.read(controlRegistryProvider).choose(listId, n);
        Analytics.track('voice_choose_item', {'ok': ok});
        return ok ? null : 'Con chưa chọn được mục đó, ${honorific} chọn lại giúp con nhé.';
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
    // "@last", "@resume"...: Vy hiểu "bài lúc nãy", "xem tiếp", "như hôm qua" và nhờ trí nhớ nghe/xem trên máy trả lời.
    if (q.startsWith('@')) return _playRecall(q.toLowerCase(), router, honorific);
    // Tìm mới thì hết chế độ duyệt: danh sách mới được đánh số và tự mở số 1 nếu im lặng như bình thường.
    _ref.read(videoBrowseProvider.notifier).set(false);
    Analytics.track('voice_play_video', {'len': q.length});
    final List<VideoItem> found;
    try {
      // Cùng số lượng với màn Giải trí (12) để kết quả dùng lại từ bộ nhớ, không tìm hai lần.
      found = await _ref.read(videoSearchProvider).search(q);
    } catch (_) {
      return 'Con tìm video chưa được, $honorific kiểm tra mạng rồi thử lại nhé.';
    }
    if (found.isEmpty) return 'Con không tìm thấy video nào về "$q" ạ.';
    _ref.read(videoQueryProvider.notifier).set(q);
    _ref.read(videoTopicProvider.notifier).set(q);
    router.go(Routes.entertainment);
    if (isVagueVideoQuery(q)) {
      // Không dùng thẻ che màn: đánh số 1, 2, 3… ngay trên các video thật của màn Giải trí.
      _ref.read(videoQueueProvider.notifier).set(found);
      _ref.read(videoMarksProvider.notifier).set(true);
      return 'Dạ, con tìm được mấy video rồi, $honorific chọn số mấy ạ?';
    }
    final first = found.first;
    _ref.read(videoQueueProvider.notifier).set(found);
    final sleep = defaultSleepMinutesFor(q);
    _ref.read(playerStartSleepProvider.notifier).set(sleep);
    router.push(Routes.player, extra: first);
    final tail = sleep == null ? '' : ' Con hẹn giờ tắt sau $sleep phút cho $honorific dễ ngủ ạ.';
    return 'Dạ, con mở ${cleanVideoTitle(first.title)} ạ.$tail';
  }

  /// Mở lại một mục trong lịch sử. [startAt] (giây) để xem tiếp đúng chỗ dở. Trả về tên bài đã làm sạch để Vy đọc.
  String _openEntry(MediaEntry e, GoRouter router, {int? startAt}) {
    final video = e.toVideo();
    _ref.read(videoQueryProvider.notifier).set(e.topic);
    _ref.read(videoTopicProvider.notifier).set(e.topic);
    _ref.read(videoQueueProvider.notifier).set([video]);
    _ref.read(playerStartAtProvider.notifier).set(startAt);
    _ref.read(playerStartSleepProvider.notifier).set(defaultSleepMinutesFor(e.topic));
    router.go(Routes.entertainment);
    router.push(Routes.player, extra: video);
    return cleanVideoTitle(e.title);
  }

  /// Nghe/xem lại theo trí nhớ: "bài lúc nãy" (@last), "xem tiếp" (@resume), "bài tôi thích" (@favorite), "như mọi khi" (@habit).
  Future<String?> _playRecall(String token, GoRouter router, String hon) async {
    Analytics.track('voice_play_recall', {'t': token});
    final mem = _ref.read(mediaMemoryProvider);
    final now = DateTime.now();
    switch (token) {
      case '@last':
        final e = mem.last;
        if (e == null) return 'Dạ, con chưa thấy $hon nghe gì gần đây ạ. ${_cap(hon)} muốn nghe gì ạ?';
        final r = mem.resumable(now);
        if (r != null && r.id == e.id) {
          final title = _openEntry(e, router, startAt: e.progressSec);
          return 'Dạ, con mở tiếp $title, từ chỗ $hon đang nghe dở ạ.';
        }
        return 'Dạ, con mở lại ${_openEntry(e, router)} ạ.';
      case '@resume':
        final r = mem.resumable(now);
        if (r == null) return 'Dạ, con không thấy bài nào $hon đang xem dở ạ.';
        final title = _openEntry(r, router, startAt: r.progressSec);
        return 'Dạ, con mở tiếp $title, từ chỗ $hon đang xem dở ạ.';
      case '@favorite':
        final liked = mem.liked;
        if (liked.isEmpty) {
          return 'Dạ, con chưa lưu bài nào $hon thích ạ. Khi đang nghe, $hon nói "bài này hay" thì con sẽ nhớ nhé.';
        }
        final title = _openEntry(liked.first, router);
        _ref.read(videoQueueProvider.notifier).set([for (final e in liked) e.toVideo()]);
        return 'Dạ, con mở bài $hon thích: $title ạ.';
      case '@habit':
        final topic = mem.suggestedTopic(now);
        if (topic == null) return 'Dạ, $hon muốn nghe gì ạ?';
        final List<VideoItem> found;
        try {
          found = await _ref.read(videoSearchProvider).search(topic);
        } catch (_) {
          return 'Con tìm video chưa được, $hon kiểm tra mạng rồi thử lại nhé.';
        }
        if (found.isEmpty) return 'Con không tìm thấy video nào về "$topic" ạ.';
        _ref.read(videoQueryProvider.notifier).set(topic);
        _ref.read(videoTopicProvider.notifier).set(topic);
        _ref.read(videoQueueProvider.notifier).set(found);
        _ref.read(playerStartSleepProvider.notifier).set(defaultSleepMinutesFor(topic));
        router.go(Routes.entertainment);
        router.push(Routes.player, extra: found.first);
        return 'Dạ, giờ này $hon hay nghe $topic, con mở ${cleanVideoTitle(found.first.title)} ạ.';
    }
    return null;
  }

  // ---- cuộn màn hình và đọc danh sách ("lướt xuống để tôi xem mấy video khác") ----

  String _listSig = '';

  /// Mục kế tiếp sẽ đọc (đếm từ 0) trong danh sách đang hiện.
  int _readNext = 0;

  static const _readBatch = 3;

  /// Danh sách đầu tiên đang hiện trên màn và dấu nhận biết để biết khi nào danh sách đổi.
  VyList? _currentList() {
    final lists = _ref.read(controlRegistryProvider).lists;
    if (lists.isEmpty) return null;
    final l = lists.first;
    final sig = '${l.id}:${l.items.length}:${l.items.isEmpty ? '' : l.items.first.title}';
    if (sig != _listSig) {
      _listSig = sig;
      _readNext = 0;
    }
    return l;
  }

  /// Đọc tối đa [_readBatch] mục từ [_readNext], hiện số trên màn, hỏi chọn.
  String _readItems(VyList l, String hon) {
    final items = l.items;
    if (_readNext >= items.length) {
      _readNext = 0;
      return 'Dạ, hết danh sách rồi ạ. ${_cap(hon)} nói "đọc lại" nếu muốn con đọc từ đầu.';
    }
    final end = (_readNext + _readBatch).clamp(0, items.length);
    final noun = l.id.startsWith('ent.') ? 'Bài' : 'Mục';
    final parts = [
      for (var i = _readNext; i < end; i++) '$noun ${i + 1}: ${cleanVideoTitle(items[i].title, maxChars: 60)}',
    ];
    _readNext = end;
    // Hiện số trên màn để người dùng chọn theo số; đang duyệt thì không tự mở video nào.
    if (l.id.startsWith('ent.')) {
      _ref.read(videoMarksProvider.notifier).set(true);
      _ref.read(videoBrowseProvider.notifier).set(true);
    }
    final more = end < items.length ? '' : ' Đó là mục cuối.';
    return '${parts.join('. ')}.$more ${_cap(hon)} chọn số mấy ạ?';
  }

  /// "Lướt xuống", "lên trên", "về đầu", "xem thêm": cuộn màn, rồi đọc ba mục mới nếu màn có danh sách.
  String? _scroll(String? dir, String hon) {
    final d = (dir ?? 'down').toLowerCase();
    final reg = _ref.read(controlRegistryProvider);
    final r = reg.scroll(d);
    Analytics.track('voice_scroll', {'dir': d, 'result': r.name});
    if (r == VyScrollResult.none) return 'Dạ, màn này con chưa cuộn được bằng giọng ạ. ${_cap(hon)} dùng ngón tay kéo giúp con nhé.';
    final l = _currentList();
    if (l == null) {
      return r == VyScrollResult.atEdge
          ? (d == 'up' || d == 'top' ? 'Dạ, đang ở đầu rồi ạ.' : 'Dạ, hết rồi ạ, không còn gì phía dưới nữa.')
          : (d == 'up' || d == 'top' ? 'Dạ, con cuộn lên rồi ạ.' : 'Dạ, con cuộn xuống rồi ạ.');
    }
    // Có danh sách: coi như hai mục đầu đã thấy; mỗi lần lướt đọc ba mục tiếp theo (hoặc ba mục trước đó khi lên).
    switch (d) {
      case 'up':
        _readNext = (_readNext - _readBatch * 2).clamp(0, l.items.length);
      case 'top':
        _readNext = 0;
      case 'bottom':
        _readNext = (l.items.length - _readBatch).clamp(0, l.items.length);
      default:
        if (_readNext == 0) _readNext = 2;
    }
    if (r == VyScrollResult.atEdge && d == 'down' && _readNext >= l.items.length) {
      return 'Dạ, hết danh sách rồi ạ, con chỉ thấy ${l.items.length} bài. ${_cap(hon)} muốn tìm cái khác thì nói với con nhé.';
    }
    return _readItems(l, hon);
  }

  /// "Đọc tên các video", "có những bài nào", "đọc tiếp": đọc ba mục kế tiếp.
  String _readList(String hon) {
    final l = _currentList();
    if (l == null) return 'Dạ, trên màn hình bây giờ con không thấy danh sách nào để đọc ạ.';
    return _readItems(l, hon);
  }

  /// Điều khiển video đang phát bằng giọng nói. [action] là tên lệnh, hoặc "back:30" / "fwd:60" / "sleep:45".
  String? _controlVideo(String? action, String honorific) {
    final raw = (action ?? '').toLowerCase().trim();
    // "Đừng gợi ý nữa": tắt gợi ý chủ động, nói được ở bất cứ màn nào (không cần đang phát video).
    if (raw == 'suggest_off') {
      unawaited(_ref.read(vySettingsProvider.notifier).setRemind(media: false));
      return 'Dạ, con sẽ không tự gợi ý nhạc, video nữa ạ. Khi nào cần, $honorific cứ nói con mở nhé.';
    }
    if (!_ref.read(playerOpenProvider)) {
      return 'Dạ, hiện chưa có video nào đang phát ạ.';
    }
    final name = raw.split(':').first;
    final number = int.tryParse(raw.contains(':') ? raw.split(':').last : '');
    final a = switch (name) {
      'pause' => PlayerAction.pause,
      'play' => PlayerAction.play,
      'next' => PlayerAction.next,
      'previous' => PlayerAction.previous,
      'louder' => PlayerAction.louder,
      'quieter' => PlayerAction.quieter,
      'restart' => PlayerAction.restart,
      'close' => PlayerAction.close,
      'back' => PlayerAction.seekBack,
      'fwd' => PlayerAction.seekForward,
      'sleep' => PlayerAction.sleep,
      'like' => PlayerAction.like,
      'dislike' => PlayerAction.dislike,
      'info' => null,
      _ => null,
    };
    if (name == 'info') {
      final now = _ref.read(playerNowProvider);
      if (now == null) return 'Dạ, con chưa biết bài đang phát là bài nào ạ.';
      final by = now.author.trim().isEmpty ? '' : ', kênh ${now.author.trim()}';
      return 'Dạ, đây là ${cleanVideoTitle(now.title)}$by ạ.';
    }
    if (a == null) return null;
    final volume = _ref.read(playerVolumeProvider);
    // Nói đúng sự thật: đã chạm trần/đáy thì không báo "đã tăng/giảm".
    if (a == PlayerAction.louder && volume >= 100) {
      return 'Dạ, trong app con đã để to hết cỡ rồi ạ. $honorific bấm nút to bên hông máy giúp con nhé.';
    }
    if (a == PlayerAction.quieter && volume <= 10) {
      return 'Dạ, con đã để nhỏ hết cỡ rồi ạ.';
    }
    final int? value = switch (a) {
      PlayerAction.seekBack || PlayerAction.seekForward => (number ?? 15).clamp(5, 600),
      PlayerAction.sleep => (number ?? 30).clamp(1, 480),
      _ => null,
    };
    final remember = _ref.read(mediaMemoryProvider.notifier).enabled;
    _ref.read(playerCommandProvider.notifier).send(a, value: value);
    Analytics.track('voice_video_control', {'action': name});
    return switch (a) {
      PlayerAction.pause => 'Dạ, con dừng rồi ạ.',
      PlayerAction.play => 'Dạ, con phát tiếp ạ.',
      PlayerAction.next => 'Dạ, con chuyển bài ạ.',
      PlayerAction.previous => 'Dạ, con mở lại bài trước ạ.',
      PlayerAction.louder => 'Dạ, con tăng âm lượng rồi ạ.',
      PlayerAction.quieter => 'Dạ, con giảm âm lượng rồi ạ.',
      PlayerAction.restart => 'Dạ, con phát lại từ đầu ạ.',
      PlayerAction.close => 'Dạ, con tắt video rồi ạ.',
      PlayerAction.seekBack => 'Dạ, con tua lại ${_spokenSeconds(value!)} ạ.',
      PlayerAction.seekForward => 'Dạ, con tua tới ${_spokenSeconds(value!)} ạ.',
      PlayerAction.like => remember
          ? 'Dạ, con nhớ bài này rồi ạ, lần sau con mở cho $honorific nghe ạ.'
          : 'Dạ, $honorific đang tắt chế độ nhớ nên con chưa lưu được ạ.',
      PlayerAction.dislike => remember ? 'Dạ, con bỏ bài này, mở bài khác ạ.' : 'Dạ, con mở bài khác ạ.',
      PlayerAction.sleep =>
        'Dạ, con sẽ tắt sau ${value! >= 60 && value % 60 == 0 ? '${value ~/ 60} tiếng' : '$value phút'} ạ.',
    };
  }

  static String _spokenSeconds(int s) {
    if (s >= 60 && s % 60 == 0) return '${s ~/ 60} phút';
    return '$s giây';
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

  /// Ghi số đo huyết áp người dùng vừa đọc (đã được xác nhận ở bước trước). Kiểm tra lại số ở app, không tin hoàn toàn máy chủ.
  Future<String> recordBp(Map<String, String> s, String honorific) async {
    final sys = int.tryParse(s['systolic'] ?? '');
    final dia = int.tryParse(s['diastolic'] ?? '');
    final pulse = int.tryParse(s['pulse'] ?? '');
    if (sys == null || dia == null) {
      return 'Con chưa ghi được số đo, $honorific đọc lại giúp con nhé.';
    }
    if (sys < 70 || sys > 260 || dia < 40 || dia > 160 || sys <= dia) {
      return 'Con nghe số đo chưa hợp lý nên con chưa ghi. ${_cap(honorific)} đọc lại giúp con nhé.';
    }
    final okPulse = pulse != null && pulse >= 30 && pulse <= 220 ? pulse : null;
    try {
      await _ref.read(bpRepositoryProvider).add(
        BpReading(
          systolic: sys,
          diastolic: dia,
          pulse: okPulse,
          measuredAt: DateTime.now(),
          source: 'manual', // cột source chỉ nhận ocr_ai/ocr_local/manual
          note: 'Nhập bằng giọng nói',
        ),
      );
    } catch (_) {
      return 'Con ghi chưa được, $honorific kiểm tra mạng rồi thử lại nhé.';
    }
    Analytics.track('voice_record_bp', {'pulse': okPulse != null});
    _ref.invalidate(bpReadingsProvider);
    final cat = BpCategory.of(sys, dia);
    final router = _ref.read(routerProvider);
    _ref.read(vyCardProvider.notifier).show(
      BpCard(
        systolic: sys,
        diastolic: dia,
        pulse: okPulse,
        levelLabel: cat.label,
        levelColor: cat.color,
        when: 'vừa ghi xong',
        actions: [
          VyCardAction(
            label: 'Xem biểu đồ',
            primary: true,
            run: () {
              _ref.read(healthTabProvider.notifier).set(0);
              router.go(Routes.bp);
            },
          ),
        ],
      ),
    );
    final pl = okPulse == null ? '' : ', mạch $okPulse';
    return 'Dạ, con đã ghi huyết áp $sys trên $dia$pl. Mức: ${cat.label}.';
  }

  /// Đọc các tin nhắn gần đây của người khác gửi cho mình (3 ngày), kèm thẻ Tin nhắn.
  Future<String> readMessages(String honorific) async {
    final List<IncomingMsg> list;
    try {
      list = await _ref.read(recentIncomingMessagesProvider.future);
    } catch (_) {
      return 'Con chưa đọc được tin nhắn, $honorific kiểm tra mạng rồi thử lại nhé.';
    }
    final cap = _cap(honorific);
    if (list.isEmpty) return '$cap không có tin nhắn mới trong mấy ngày qua ạ.';
    final router = _ref.read(routerProvider);
    _ref.read(vyCardProvider.notifier).show(
      MsgCard(
        actions: [
          // Trả lời qua đúng luồng gửi tin (hỏi nội dung → xác nhận → gửi), không có đường tắt gửi thẳng.
          VyCardAction(label: 'Trả lời ${list.first.from}', primary: true, keepOpen: true, run: () => unawaited(_ref.read(vyCoreProvider.notifier).sendText('nhắn cho ${list.first.from}'))),
          VyCardAction(label: 'Dạ', keepOpen: true, run: () => unawaited(_ref.read(vyCoreProvider.notifier).sendText('nhắn cho ${list.first.from} là dạ'))),
        ],
        rows: [
          for (final m in list.take(3))
            MsgRow(
              from: m.from,
              time: _whenText(m.at),
              text: m.text,
              onOpen: () {
                router.go(Routes.rooms);
                router.push(Routes.roomPath(m.roomId));
              },
            ),
        ],
      ),
    );
    // Đọc to tối đa 2 tin mới nhất (từng tin ngắn gọn); còn lại xem trong thẻ.
    final spoken = list.take(2).map((m) => '${m.from} nhắn: ${m.text}').join('. ');
    final more = list.length > 2 ? ' Còn ${list.length - 2} tin nữa trong thẻ.' : '';
    return '$cap có ${list.length} tin nhắn. $spoken.$more $cap muốn trả lời ${list.first.from} không ạ?';
  }

  /// Gọi điện: tìm số trong thẻ y tế (người liên hệ) hoặc 115, rồi hiện thẻ đếm ngược 3 giây (2 giây cho 115) có nút Huỷ.
  Future<String> callContact(String who, String honorific) async {
    final cap = _cap(honorific);
    final q = viNorm(who);
    if (q.isEmpty) return 'Dạ, $honorific muốn gọi cho ai ạ?';
    String name;
    String number;
    var seconds = 3;
    if (q == '115' || q == 'cap cuu' || q.contains('cuu thuong')) {
      name = 'Cấp cứu 115';
      number = '115';
      seconds = 2;
    } else {
      final uid = _ref.read(currentUserProvider)?.id;
      EmergencyCard? card;
      try {
        card = uid == null ? null : await _ref.read(emergencyCardProvider(uid).future);
      } catch (_) {}
      final people = <CardContact>[
        ...?card?.contacts.where((c) => c.phone.trim().isNotEmpty),
      ];
      // Người thân đã liên kết với mình (con, cháu, vợ/chồng): để "gọi con trai" ghép được với số trong thẻ.
      var linked = <({String name, String relation, String? phone})>[];
      try {
        final links = (await _ref.read(familyLinksProvider.future)).where((l) => l.iAmOwner && l.active).toList();
        // Số điện thoại người thân tự điền ở Hồ sơ của họ (máy chủ chỉ trả số của người đang liên kết với mình).
        Map<String, String> phones = const {};
        try {
          phones = await _ref.read(phoneRepositoryProvider).ofUsers([for (final l in links) l.otherId]);
        } catch (_) {}
        linked = [
          for (final l in links)
            (name: (l.otherName ?? l.otherUsername ?? '').trim(), relation: l.relation.code, phone: phones[l.otherId]),
        ];
      } catch (_) {}
      final r = resolveCallee(q, people, linked);
      switch (r) {
        case CalleeFound(:final contact):
          name = contact.name.isEmpty ? contact.phone : contact.name;
          number = contact.phone;
        case CalleeMany(:final contacts):
          return 'Con thấy nhiều người giống vậy: ${contacts.take(3).map((c) => c.name).join(', ')}. $cap nói rõ tên giúp con nhé.';
        case CalleeNoNumber(:final person):
          final me = uid;
          if (me != null) {
            final router = _ref.read(routerProvider);
            _ref.read(vyCardProvider.notifier).show(
              NoticeCard(
                title: 'Chưa có số của $person',
                body: 'Nhờ $person điền số ở Hồ sơ của họ, hoặc thêm số của $person ở Thẻ y tế khẩn cấp để Vy gọi giúp.',
                actions: [
                  VyCardAction(label: 'Mở thẻ y tế', primary: true, run: () => router.push(Routes.emergencyCardFor(me))),
                ],
              ),
            );
          }
          return 'Con thấy $person trong người thân của $honorific nhưng chưa có số điện thoại. $cap thêm số ở Thẻ y tế khẩn cấp giúp con nhé.';
        case CalleeNone():
          return 'Con chưa thấy số của "${who.trim()}" trong thẻ y tế khẩn cấp. $cap thêm người liên hệ ở Hồ sơ giúp con nhé.';
      }
    }
    final call = _ref.read(directCallProvider);
    _ref.read(vyCardProvider.notifier).show(
      CallCard(
        name: name,
        number: number,
        seconds: seconds,
        onCall: () {
          Analytics.track('voice_call', {'emergency': number == '115'});
          unawaited(call(number));
        },
        actions: [
          VyCardAction(label: 'Huỷ', primary: true, run: () => _ref.read(vyCardProvider.notifier).clear()),
        ],
      ),
    );
    return 'Dạ, con gọi $name sau $seconds giây. $cap bấm Huỷ nếu không muốn gọi ạ.';
  }

  /// SOS bằng giọng: người dùng NÓI RÕ "gọi SOS" thì đếm ngược 5 giây có nút Huỷ rồi báo người thân (D18).
  /// Vy không tự bắt đầu; thẻ bị gỡ (đóng Vy, nói việc khác) trước khi hết giờ thì KHÔNG báo.
  Future<String> startSos(String honorific) async {
    final cap = _cap(honorific);
    Analytics.track('voice_sos_start');
    _ref.read(vyCardProvider.notifier).show(
      SosCard(
        seconds: 5,
        onFire: () => unawaited(fireSos()),
        actions: [
          VyCardAction(
            label: 'Huỷ',
            primary: true,
            run: () {
              Analytics.track('voice_sos_cancel');
              _ref.read(vyCardProvider.notifier).clear();
            },
          ),
        ],
      ),
    );
    return 'Dạ, con báo SOS cho người thân sau 5 giây. $cap bấm Huỷ nếu bấm nhầm ạ.';
  }

  /// Báo SOS thật (như bấm giữ nút SOS) rồi mở màn SOS. Mất mạng thì vẫn mở màn SOS để gọi 115.
  Future<void> fireSos() async {
    Analytics.track('sos_trigger', {'via': 'voice'});
    String id;
    try {
      id = await _ref.read(safetyRepositoryProvider).triggerSos();
    } catch (_) {
      id = sosFailedId;
    }
    _ref.read(vyCardProvider.notifier).clear();
    unawaited(_ref.read(vyCoreProvider.notifier).close(reason: 'sos'));
    _ref.read(routerProvider).push(Routes.sosFor(id));
  }

  /// Tìm người cần gọi: trước hết trong người liên hệ của thẻ y tế (theo tên); nếu không có thì theo QUAN HỆ/tên của người thân
  /// đã liên kết ("con trai" → người liên kết có quan hệ "con") rồi ghép tên đó với số trong thẻ.
  static Callee resolveCallee(String q, List<CardContact> people, List<({String name, String relation, String? phone})> linked) {
    final direct = matchContacts(q, people);
    if (direct.length == 1) return CalleeFound(direct.first);
    if (direct.length > 1) return CalleeMany(direct);
    final qt = q.split(' ').where((w) => w.isNotEmpty).toSet();
    final wantRel = <String>{
      if (qt.contains('con')) 'con',
      if (qt.contains('chau')) 'chau',
      if (qt.contains('vo') || qt.contains('chong')) 'vo_chong',
    };
    final persons = [
      for (final l in linked)
        if (l.name.isNotEmpty &&
            (wantRel.contains(l.relation) || viNorm(l.name) == q || (q.length >= 3 && viNorm(l.name).contains(q))))
          l,
    ];
    if (persons.isEmpty) return const CalleeNone();
    final hits = <CardContact>[];
    void add(CardContact c) {
      if (!hits.any((h) => dialable(h.phone) == dialable(c.phone))) hits.add(c);
    }

    for (final l in persons) {
      // Số trong thẻ y tế (người dùng tự ghi) được ưu tiên; không có thì dùng số người thân tự điền ở Hồ sơ của họ.
      final fromCard = matchContacts(viNorm(l.name), people);
      if (fromCard.isNotEmpty) {
        fromCard.forEach(add);
      } else if ((l.phone ?? '').isNotEmpty) {
        add(CardContact(name: l.name, phone: l.phone!));
      }
    }
    if (hits.length == 1) return CalleeFound(hits.first);
    if (hits.length > 1) return CalleeMany(hits);
    return CalleeNoNumber(persons.first.name);
  }

  /// Người liên hệ khớp với cụm đã bỏ dấu [q]: tên chứa cụm, cụm chứa tên, hoặc mọi từ của cụm có trong tên.
  static List<CardContact> matchContacts(String q, List<CardContact> people) {
    final qt = q.split(' ').where((w) => w.isNotEmpty).toList();
    final out = <CardContact>[];
    for (final c in people) {
      final n = viNorm(c.name);
      if (n.isEmpty) continue;
      final nt = n.split(' ');
      if (n == q || n.contains(q) || q.contains(n) || qt.every(nt.contains)) out.add(c);
    }
    return out;
  }

  static String _cap(String h) => h.isEmpty ? h : '${h[0].toUpperCase()}${h.substring(1)}';

  /// "hôm nay 07:05", "hôm qua 19:30", "12/11 08:00".
  static String _whenText(DateTime t, [DateTime? now]) {
    final n = now ?? DateTime.now();
    final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final d = DateTime(t.year, t.month, t.day);
    final today = DateTime(n.year, n.month, n.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'hôm nay $hm';
    if (diff == 1) return 'hôm qua $hm';
    return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} $hm';
  }

  /// Đọc cữ thuốc kế tiếp và các cữ hôm nay, kèm thẻ Thuốc.
  Future<String> readMeds(String honorific, {bool forgot = false}) async {
    final cap = '${honorific[0].toUpperCase()}${honorific.substring(1)}';
    final List<Dose> all;
    try {
      all = await _ref.read(myDosesProvider.future);
    } catch (_) {
      return 'Con chưa đọc được lịch thuốc, $honorific thử lại sau nhé.';
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todays = [
      for (final d in all)
        if (!d.dueAt.isBefore(today) && d.dueAt.isBefore(today.add(const Duration(days: 1)))) d,
    ]..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    if (todays.isEmpty) {
      return 'Hôm nay $honorific không có cữ thuốc nào ạ.';
    }
    Dose? next;
    for (final d in todays) {
      final st = d.stateAt(now);
      if (st == DoseState.due || st == DoseState.upcoming) {
        next = d;
        break;
      }
    }
    (String, Color) status(Dose d) => switch (d.stateAt(now)) {
      DoseState.taken => ('Đã uống', AppColors.levelGood),
      DoseState.skipped => ('Đã bỏ qua', AppColors.textMuted),
      DoseState.missed => ('Chưa uống, quá giờ', AppColors.levelDanger),
      DoseState.due => ('Đến giờ', AppColors.navy),
      DoseState.upcoming => ('Sắp tới', AppColors.textMuted),
    };
    // Cữ đã quá giờ mà chưa uống (kể cả cữ chờ máy chủ đánh dấu): Vy nói ra và cho ghi "đã uống" ngay trên thẻ.
    final missed = [for (final d in todays) if (d.stateAt(now) == DoseState.missed) d];
    final router = _ref.read(routerProvider);
    _ref.read(vyCardProvider.notifier).show(
      MedCard(
        title: missed.isNotEmpty ? 'Còn ${missed.length} cữ chưa uống' : (next != null ? 'Cữ kế tiếp lúc ${next.hm}' : 'Thuốc hôm nay'),
        rows: [
          for (final d in todays)
            MedRow(
              time: d.hm,
              name: d.bag ? 'Túi ${d.label}' : d.label,
              status: status(d).$1,
              statusColor: status(d).$2,
              items: [for (final i in d.items) i.text],
              highlight: d.id == next?.id,
            ),
        ],
        actions: [
          for (final m in missed.take(2))
            VyCardAction(
              label: 'Đã uống ${m.bag ? 'túi ' : ''}${m.label}',
              primary: true,
              run: () async {
                Analytics.track('vy_dose_mark', {'via': 'card_missed'});
                try {
                  await _ref.read(medsRepositoryProvider).setDose(m.id, 'taken');
                } catch (_) {}
                _ref
                  ..invalidate(myDosesProvider)
                  ..invalidate(myPlansProvider);
              },
            ),
          VyCardAction(
            label: 'Mở màn thuốc',
            primary: missed.isEmpty,
            run: () {
              _ref.read(healthTabProvider.notifier).set(2);
              router.go(Routes.bp);
            },
          ),
        ],
      ),
    );
    final names = missed.map((d) => '${d.bag ? 'túi ' : ''}${d.label.toLowerCase()} lúc ${d.hm}').join(' và ');
    final lead = missed.isNotEmpty
        ? 'Hôm nay $honorific chưa uống $names ạ. $cap uống bù rồi thì nói "uống rồi" để con ghi lại nhé. '
        : (forgot ? 'Hôm nay $honorific không quên cữ nào ạ. ' : '');
    if (next == null) {
      return missed.isNotEmpty ? lead.trim() : '$lead$cap đã xong các cữ thuốc hôm nay rồi ạ.'.trim();
    }
    final left = todays
        .where((d) => d.id != next!.id && (d.stateAt(now) == DoseState.upcoming || d.stateAt(now) == DoseState.due))
        .length;
    final more = left > 0 ? ' Hôm nay còn $left cữ nữa.' : '';
    return '${lead}Cữ kế tiếp lúc ${next.hm}: ${next.what}.$more';
  }

  /// Các cữ hôm nay đang chờ ghi (đã đến giờ hoặc quá giờ, chưa uống/bỏ qua), mới nhất trước.
  Future<List<Dose>?> _openDoses() async {
    try {
      final all = await _ref.read(myDosesProvider.future);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final list = [
        for (final d in all)
          if (d.status != 'taken' &&
              d.status != 'skipped' &&
              !d.dueAt.isBefore(today) &&
              d.dueAt.isBefore(today.add(const Duration(days: 1))) &&
              !d.dueAt.isAfter(now.add(Dose.earlyWindow)))
            d,
      ]..sort((a, b) => b.dueAt.compareTo(a.dueAt));
      return list;
    } catch (_) {
      return null;
    }
  }

  /// Người dùng nói "uống rồi": ghi cữ vừa đến giờ gần nhất là đã uống (có nút hoàn tác). Còn cữ khác chưa ghi thì hỏi tiếp.
  Future<String> markDoseTaken(String honorific) async {
    final open = await _openDoses();
    if (open == null) return 'Con chưa ghi được, $honorific bấm "Đã uống" ở màn thuốc giúp con nhé.';
    if (open.isEmpty) return 'Dạ, các cữ đến giờ đều đã ghi là uống rồi ạ.';
    final d = open.first;
    final repo = _ref.read(medsRepositoryProvider);
    try {
      await repo.setDose(d.id, 'taken');
    } catch (_) {
      return 'Con chưa ghi được, $honorific bấm "Đã uống" ở màn thuốc giúp con nhé.';
    }
    Analytics.track('vy_dose_mark', {'via': 'voice'});
    _ref
      ..invalidate(myDosesProvider)
      ..invalidate(myPlansProvider);
    final others = open.skip(1).toList();
    final name = '${d.bag ? 'túi ' : ''}${d.label.toLowerCase()}';
    _ref.read(vyCardProvider.notifier).show(
      NoticeCard(
        title: 'Đã ghi uống $name',
        body: '${d.hm}${others.isEmpty ? '' : '\nCòn chưa ghi: ${others.map((o) => '${o.bag ? 'túi ' : ''}${o.label} ${o.hm}').join(', ')}'}',
        actions: [
          for (final o in others.take(2))
            VyCardAction(
              label: 'Đã uống ${o.bag ? 'túi ' : ''}${o.label}',
              primary: true,
              run: () async {
                Analytics.track('vy_dose_mark', {'via': 'card_other'});
                try {
                  await repo.setDose(o.id, 'taken');
                } catch (_) {}
                _ref
                  ..invalidate(myDosesProvider)
                  ..invalidate(myPlansProvider);
              },
            ),
          VyCardAction(
            label: 'Hoàn tác',
            run: () async {
              try {
                await repo.setDose(d.id, 'pending');
              } catch (_) {}
              _ref
                ..invalidate(myDosesProvider)
                ..invalidate(myPlansProvider);
            },
          ),
        ],
      ),
    );
    final tail = others.isEmpty
        ? ''
        : ' Còn ${others.length == 1 ? '${others.first.bag ? 'túi ' : ''}${others.first.label.toLowerCase()} lúc ${others.first.hm}' : '${others.length} cữ nữa'} chưa ghi, $honorific đã uống chưa ạ?';
    return 'Dạ, con ghi $honorific đã uống $name rồi ạ.$tail';
  }

  /// Người dùng nói "lát nữa uống": hoãn nhắc cữ đang chờ 15 phút.
  Future<String> snoozeDose(String honorific) async {
    final open = await _openDoses();
    if (open == null || open.isEmpty) return 'Dạ, hiện không có cữ nào đang chờ ạ.';
    final d = open.first;
    try {
      await _ref.read(medsRepositoryProvider).snooze(d.id, 15);
    } catch (_) {
      return 'Con chưa hoãn được ạ.';
    }
    Analytics.track('vy_dose_snooze', {'via': 'voice'});
    _ref.invalidate(myDosesProvider);
    return 'Dạ, 15 phút nữa con nhắc $honorific uống ${d.bag ? 'túi ' : ''}${d.label.toLowerCase()} nhé.';
  }

  Future<String> readBp(String honorific) async {
    try {
      final list = await _ref.read(bpReadingsProvider.future);
      if (list.isEmpty)
        return 'Chưa có kết quả đo nào. ${honorific[0].toUpperCase()}${honorific.substring(1)} đo huyết áp rồi chụp lại giúp con nhé.';
      final r = list.reduce(
        (a, b) => a.measuredAt.isAfter(b.measuredAt) ? a : b,
      );
      final cat = BpCategory.of(r.systolic, r.diastolic);
      final pulse = r.pulse == null ? '' : ', mạch ${r.pulse}';
      final router = _ref.read(routerProvider);
      _ref.read(vyCardProvider.notifier).show(
        BpCard(
          systolic: r.systolic,
          diastolic: r.diastolic,
          pulse: r.pulse,
          levelLabel: cat.label,
          levelColor: cat.color,
          when: _whenText(r.measuredAt),
          actions: [
            VyCardAction(
              label: 'Xem biểu đồ',
              primary: true,
              run: () {
                _ref.read(healthTabProvider.notifier).set(0);
                router.go(Routes.bp);
              },
            ),
            VyCardAction(label: 'Đo lại', run: () => router.push(Routes.measure)),
          ],
        ),
      );
      return 'Lần đo gần nhất: huyết áp ${r.systolic} trên ${r.diastolic}$pulse. Mức: ${cat.label}.';
    } catch (_) {
      return 'Con chưa đọc được kết quả, $honorific thử lại sau nhé.';
    }
  }
}

final voiceActionsProvider = Provider<VoiceActions>(VoiceActions.new);

/// Một tin nhắn người khác gửi cho mình (để Vy đọc).
class IncomingMsg {
  const IncomingMsg({required this.roomId, required this.from, required this.text, required this.at, this.content = ''});

  final String roomId;
  final String from;

  /// Lời Vy đọc (đã rút gọn, tin hình thì "gửi một hình ảnh").
  final String text;
  final DateTime at;

  /// Nội dung gốc đầy đủ (để nhận ra video người thân gửi, không bị cắt giữa đường dẫn).
  final String content;
}

/// Tin nhắn người khác gửi trong 3 ngày qua (mới nhất trước, tối đa 5). Tin chỉ có hình thì đọc là "gửi một hình ảnh".
final recentIncomingMessagesProvider = FutureProvider.autoDispose<List<IncomingMsg>>((ref) async {
  final c = ref.read(supabaseClientProvider);
  final uid = c.auth.currentUser?.id;
  if (uid == null) return const [];
  final since = DateTime.now().subtract(const Duration(days: 3)).toUtc().toIso8601String();
  final rows = await c
      .from('messages')
      .select('room_id, user_id, content, image_path, created_at')
      .neq('user_id', uid)
      .gte('created_at', since)
      .order('created_at', ascending: false)
      .limit(5);
  final rooms = await ref.read(roomsProvider.future);
  final names = {for (final r in rooms) r.id: r.displayName};
  return [
    for (final r in rows)
      IncomingMsg(
        roomId: r['room_id'] as String,
        from: names[r['room_id']] ?? 'Người thân',
        text: _spokenText((r['content'] as String?) ?? '', r['image_path'] != null),
        content: (r['content'] as String?) ?? '',
        at: DateTime.parse(r['created_at'] as String).toLocal(),
      ),
  ];
});

String _spokenText(String content, bool hasImage) {
  final video = parseSharedVideo(content);
  if (video != null) return 'gửi một video: ${cleanVideoTitle(video.title, maxChars: 80)}';
  final t = content.trim();
  if (t.isEmpty) return hasImage ? 'gửi một hình ảnh' : '(tin trống)';
  return t.length > 200 ? '${t.substring(0, 200)}…' : t;
}

/// Kết quả tìm người cần gọi.
sealed class Callee {
  const Callee();
}

class CalleeFound extends Callee {
  const CalleeFound(this.contact);
  final CardContact contact;
}

class CalleeMany extends Callee {
  const CalleeMany(this.contacts);
  final List<CardContact> contacts;
}

/// Có người thân khớp (theo quan hệ/tên) nhưng chưa có số điện thoại trong thẻ y tế.
class CalleeNoNumber extends Callee {
  const CalleeNoNumber(this.person);
  final String person;
}

class CalleeNone extends Callee {
  const CalleeNone();
}
