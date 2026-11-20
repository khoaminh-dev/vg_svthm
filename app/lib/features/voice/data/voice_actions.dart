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
import '../../safety/domain/safety_models.dart' show CardContact, EmergencyCard;
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

  /// Lệnh đổi màn hình: chạy xong thì Vy thường thu gọn màn Vy để người dùng thấy kết quả.
  static const navIntents = {
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
        return await readMeds(honorific);
      case 'record_bp':
        return await recordBp(s, honorific);
      case 'read_messages':
        return await readMessages(honorific);
      case 'sos_start':
        return startSos(honorific);
      case 'call_contact':
        return await callContact(s['recipient_text'] ?? '', honorific);
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
      // Không dùng thẻ che màn: đánh số 1, 2, 3… ngay trên các video thật của màn Giải trí.
      _ref.read(videoQueueProvider.notifier).set(found);
      _ref.read(videoMarksProvider.notifier).set(true);
      return 'Dạ, con tìm được mấy video rồi, $honorific chọn số mấy ạ?';
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
    return '$cap có ${list.length} tin nhắn. $spoken.$more';
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
      final hits = matchContacts(q, people);
      if (hits.isEmpty) {
        return 'Con chưa thấy số của "${who.trim()}" trong thẻ y tế khẩn cấp. $cap thêm người liên hệ ở Hồ sơ giúp con nhé.';
      }
      if (hits.length > 1) {
        return 'Con thấy nhiều người giống vậy: ${hits.take(3).map((c) => c.name).join(', ')}. $cap nói rõ tên giúp con nhé.';
      }
      name = hits.first.name.isEmpty ? hits.first.phone : hits.first.name;
      number = hits.first.phone;
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
  Future<String> readMeds(String honorific) async {
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
    final router = _ref.read(routerProvider);
    _ref.read(vyCardProvider.notifier).show(
      MedCard(
        title: next != null ? 'Cữ kế tiếp lúc ${next.hm}' : 'Thuốc hôm nay',
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
          VyCardAction(
            label: 'Mở màn thuốc',
            primary: true,
            run: () {
              _ref.read(healthTabProvider.notifier).set(2);
              router.go(Routes.bp);
            },
          ),
        ],
      ),
    );
    if (next == null) {
      return '$cap đã xong các cữ thuốc hôm nay rồi ạ.';
    }
    final left = todays
        .where((d) => d.id != next!.id && (d.stateAt(now) == DoseState.upcoming || d.stateAt(now) == DoseState.due))
        .length;
    final more = left > 0 ? ' Hôm nay còn $left cữ nữa.' : '';
    return 'Cữ kế tiếp lúc ${next.hm}: ${next.what}.$more';
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
  const IncomingMsg({required this.roomId, required this.from, required this.text, required this.at});

  final String roomId;
  final String from;
  final String text;
  final DateTime at;
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
        at: DateTime.parse(r['created_at'] as String).toLocal(),
      ),
  ];
});

String _spokenText(String content, bool hasImage) {
  final t = content.trim();
  if (t.isEmpty) return hasImage ? 'gửi một hình ảnh' : '(tin trống)';
  return t.length > 200 ? '${t.substring(0, 200)}…' : t;
}
