import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vg_svthm/core/router/routes.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/features/chat/domain/message.dart';
import 'package:vg_svthm/features/chat/presentation/widgets/message_bubble.dart';
import 'package:vg_svthm/features/entertainment/data/media_memory.dart';
import 'package:vg_svthm/features/entertainment/data/media_suggest.dart';
import 'package:vg_svthm/features/entertainment/data/media_summary.dart';
import 'package:vg_svthm/features/entertainment/data/shared_video.dart';
import 'package:vg_svthm/features/entertainment/data/youtube_service.dart';
import 'package:vg_svthm/features/entertainment/presentation/entertainment_providers.dart';
import 'package:vg_svthm/features/voice/core/vy_reminders.dart';
import 'package:vg_svthm/features/voice/core/vy_settings.dart';

VideoItem v(String id, String title, {int secs = 240}) =>
    VideoItem(id: id, title: title, author: 'K', thumbnailUrl: '', duration: Duration(seconds: secs));

/// Thứ Sáu 20/11/2026.
DateTime at(int h, [int m = 0, int daysAgo = 0]) => DateTime(2026, 11, 20 - daysAgo, h, m);

/// Quen nghe [topic] vào [hour] giờ sáng suốt [n] ngày trước đó (mỗi ngày một bài).
MediaMemory habitual(String topic, int hour, {int n = 3, int startDaysAgo = 1}) {
  var m = const MediaMemory();
  for (var i = 0; i < n; i++) {
    m = m.recordPlay(v('${topic.hashCode}-$i', '$topic $i'), topic, at(hour, 10, startDaysAgo + i));
  }
  return m;
}

void main() {
  group('gợi ý chủ động: khi nào Vy nên mở lời', () {
    test('quen nghe nhạc xưa lúc 8 giờ sáng: gợi ý đúng giờ quen, một mã cho mỗi buổi', () {
      final m = habitual('nhạc xưa', 8);
      final s = suggestMedia(now: at(8, 30), memory: m);
      expect(s, isNotNull);
      expect(s!.topic, 'nhạc xưa');
      expect(s.key, 'media:2026-11-20:morning');
      // cả khoảng quanh giờ quen: 7 giờ (trước 1 giờ) đến 10:59 (sau 2 giờ)
      expect(suggestMedia(now: at(7, 5), memory: m), isNotNull);
      expect(suggestMedia(now: at(10, 50), memory: m), isNotNull);
      expect(suggestMedia(now: at(6, 30), memory: m), isNull, reason: 'còn quá sớm so với giờ quen');
    });

    test('chưa đủ thói quen thì im lặng (cần ≥ 2 lượt cùng khung giờ)', () {
      expect(suggestMedia(now: at(8, 30), memory: const MediaMemory()), isNull);
      expect(suggestMedia(now: at(8, 30), memory: habitual('nhạc xưa', 8, n: 1)), isNull);
    });

    test('thói quen buổi tối thì buổi sáng không gợi ý', () {
      final m = habitual('cải lương', 20);
      expect(suggestMedia(now: at(8, 30), memory: m), isNull);
      expect(suggestMedia(now: at(20, 15), memory: m)?.topic, 'cải lương');
    });

    test('hôm nay đã nghe trong buổi này rồi thì thôi, không gợi ý thêm', () {
      var m = habitual('nhạc xưa', 8);
      m = m.recordPlay(v('hom-nay', 'Đã nghe sáng nay'), 'nhạc xưa', at(8, 5));
      expect(suggestMedia(now: at(8, 30), memory: m), isNull);
    });

    test('ban đêm không bao giờ gợi ý; bài đã chê không góp thói quen; quá 45 ngày bỏ', () {
      final late = habitual('nhạc ru ngủ', 23);
      expect(suggestMedia(now: at(23, 10), memory: late), isNull);
      var m = habitual('nhạc xưa', 8, n: 2);
      m = m.setDisliked(m.entries[0].id, true).setDisliked(m.entries[1].id, true);
      expect(suggestMedia(now: at(8, 30), memory: m), isNull);
      expect(suggestMedia(now: at(8, 30), memory: habitual('nhạc xưa', 8, startDaysAgo: 60)), isNull);
    });

    test('chọn chủ đề nghe nhiều nhất trong khung giờ đó', () {
      var m = habitual('nhạc xưa', 8, n: 2);
      for (var i = 0; i < 4; i++) {
        m = m.recordPlay(v('dg$i', 'Dưỡng sinh $i'), 'tập dưỡng sinh', at(8, 0, 3 + i));
      }
      expect(suggestMedia(now: at(8, 20), memory: m)?.topic, 'tập dưỡng sinh');
    });
  });

  group('gợi ý chủ động: xếp sau việc quan trọng và không nói dồn', () {
    ReminderInputs inp({String? media, String? dose, bool busy = false, bool quiet = false, bool eMedia = true, DateTime? now}) =>
        ReminderInputs(
          now: now ?? at(8, 30),
          foreground: true,
          busy: busy,
          quiet: quiet,
          doseKey: dose,
          mediaKey: media,
          enabledMedia: eMedia,
        );
    const key = 'media:2026-11-20:morning';

    test('chỉ có gợi ý thì nhắc gợi ý', () {
      expect(decideReminder(inp(media: key), ReminderMemory())?.kind, ReminderKind.media);
    });

    test('thuốc luôn đi trước gợi ý', () {
      expect(decideReminder(inp(media: key, dose: 'dose:a:0'), ReminderMemory())?.kind, ReminderKind.dose);
    });

    test('đang bận, giờ yên tĩnh, đã tắt gợi ý: không nhắc', () {
      expect(decideReminder(inp(media: key, busy: true), ReminderMemory()), isNull);
      expect(decideReminder(inp(media: key, quiet: true), ReminderMemory()), isNull);
      expect(decideReminder(inp(media: key, eMedia: false), ReminderMemory()), isNull);
    });

    test('một lần cho mỗi buổi: đã nhắc rồi thì không nhắc lại (kể cả mở lại app)', () {
      final mem = ReminderMemory();
      mem.markShown(decideReminder(inp(media: key), mem)!, at(8, 30));
      expect(decideReminder(inp(media: key, now: at(9, 30)), mem), isNull);
      final saved = mem.snapshot(at(8, 31));
      final reopened = ReminderMemory()..restore(saved, at(8, 40));
      expect(decideReminder(inp(media: key, now: at(9, 0)), reopened), isNull);
    });

    test('vừa nhắc việc khác (dưới 30 phút) thì gợi ý chờ, không nói dồn', () {
      final mem = ReminderMemory();
      mem.markShown(const ReminderPick(ReminderKind.dose, 'dose:a:0'), at(8, 10));
      expect(decideReminder(inp(media: key, now: at(8, 25)), mem), isNull);
      expect(decideReminder(inp(media: key, now: at(8, 45)), mem)?.kind, ReminderKind.media);
    });

    test('câu Vy nói và xưng hô', () {
      expect(reminderSpeech(ReminderKind.media, 'bác', topic: 'nhạc xưa'), 'Giờ này bác hay nghe nhạc xưa. Bác có muốn con mở không ạ?');
    });
  });

  group('video người thân gửi', () {
    test('gửi và nhận lại đúng: tên video và đường dẫn', () {
      final text = encodeSharedVideo(v('dQw4w9WgXcQ', 'Đường chiều - Khánh Ly'));
      expect(text, '🎬 Đường chiều - Khánh Ly\nhttps://www.youtube.com/watch?v=dQw4w9WgXcQ');
      final back = parseSharedVideo(text)!;
      expect(back.id, 'dQw4w9WgXcQ');
      expect(back.title, 'Đường chiều - Khánh Ly');
    });

    test('nhận ra các dạng đường dẫn YouTube người thân hay dán', () {
      for (final url in [
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://youtube.com/watch?feature=share&v=dQw4w9WgXcQ&t=10',
        'https://youtu.be/dQw4w9WgXcQ?si=abc',
        'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://www.youtube.com/shorts/dQw4w9WgXcQ',
        'youtube.com/embed/dQw4w9WgXcQ',
      ]) {
        expect(parseSharedVideo('Mẹ xem cái này $url').toString().isNotEmpty, isTrue);
        expect(parseSharedVideo('Mẹ xem cái này $url')?.id, 'dQw4w9WgXcQ', reason: url);
      }
      expect(parseSharedVideo('https://youtu.be/dQw4w9WgXcQ')?.title, 'Video người thân gửi');
      expect(parseSharedVideo('Mẹ xem cái này https://youtu.be/dQw4w9WgXcQ')?.title, 'Mẹ xem cái này');
    });

    test('không nhầm tin nhắn thường hay đường dẫn khác', () {
      expect(parseSharedVideo('Tối nay con về ăn cơm'), isNull);
      expect(parseSharedVideo('https://facebook.com/watch?v=dQw4w9WgXcQ'), isNull);
      expect(parseSharedVideo('https://youtube.com/watch?v=ngan'), isNull);
      expect(parseSharedVideo(''), isNull);
    });

    test('tiêu đề dài bị cắt gọn khi gửi', () {
      final text = encodeSharedVideo(v('dQw4w9WgXcQ', 'Rất dài ' * 40));
      expect(parseSharedVideo(text)!.title.length, lessThanOrEqualTo(121));
    });

    test('Vy báo bằng tên sạch và hỏi một câu', () {
      expect(
        sharedVideoSpeech('bác', 'Con gái', '🎵 Đường chiều (Official MV) #shorts'),
        'Con gái gửi bác một video: Đường chiều. Bác xem luôn không ạ?',
      );
    });

    Message msg(String content) => Message(
      id: 1,
      roomId: 'r',
      userId: 'u2',
      content: content,
      createdAt: DateTime(2026, 11, 20, 9),
    );

    Widget bubble(Message m, ProviderContainer c) {
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => Scaffold(body: MessageBubble(message: m, isMine: false, senderName: 'Lan'))),
        GoRoute(path: Routes.player, builder: (_, s) => Scaffold(body: Text('PLAYER ${(s.extra as VideoItem).id}'))),
      ]);
      return UncontrolledProviderScope(
        container: c,
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      );
    }

    testWidgets('bong bóng chat hiện thẻ video thay vì đường dẫn; chạm là xem, không nối video lạ', (t) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await t.pumpWidget(bubble(msg(encodeSharedVideo(v('dQw4w9WgXcQ', 'Đường chiều'))), c));
      expect(find.byKey(const Key('shared-video')), findsOneWidget);
      expect(find.text('Đường chiều'), findsOneWidget);
      expect(find.textContaining('youtube.com'), findsNothing);
      await t.tap(find.byKey(const Key('shared-video')));
      await t.pumpAndSettle();
      expect(find.text('PLAYER dQw4w9WgXcQ'), findsOneWidget);
      expect(c.read(videoQueueProvider).single.id, 'dQw4w9WgXcQ');
      expect(c.read(videoTopicProvider), '', reason: 'không đặt chủ đề nên không tự nối video lạ');
    });

    testWidgets('tin nhắn thường vẫn hiện chữ như cũ', (t) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await t.pumpWidget(bubble(msg('Tối nay con về ăn cơm'), c));
      expect(find.text('Tối nay con về ăn cơm'), findsOneWidget);
      expect(find.byKey(const Key('shared-video')), findsNothing);
    });
  });

  group('tóm tắt cho người thân', () {
    MediaDay d(int daysAgo, String topic, int secs, {int plays = 1}) =>
        MediaDay(day: DateTime(2026, 11, 20 - daysAgo), topic: topic, seconds: secs, plays: plays);

    test('hôm nay nghe gì bao lâu, cả tuần nhiều nhất là gì', () {
      final s = summarizeMedia([
        d(0, 'nhạc xưa', 2400),
        d(0, 'Nhạc xưa', 600), // cùng thể loại khác cách viết: gộp
        d(0, 'cải lương', 1500),
        d(1, 'cải lương', 5400),
        d(3, 'tin tức', 900),
      ], DateTime(2026, 11, 20, 18));
      expect(s.today.map((t) => t.topic), ['nhạc xưa', 'cải lương']);
      expect(s.today.first.seconds, 3000);
      expect(s.weekSeconds, 2400 + 600 + 1500 + 5400 + 900);
      expect(s.topTopic, 'cải lương');
      expect(s.activeDays, 3);
      expect(s.isEmpty, isFalse);
    });

    test('chưa có gì thì rỗng', () {
      final s = summarizeMedia(const [], DateTime(2026, 11, 20));
      expect(s.isEmpty, isTrue);
      expect(s.today, isEmpty);
      expect(s.topTopic, isNull);
    });

    test('chỉ có hôm qua: "hôm nay" trống nhưng cả tuần vẫn có', () {
      final s = summarizeMedia([d(1, 'nhạc xưa', 1800)], DateTime(2026, 11, 20));
      expect(s.today, isEmpty);
      expect(s.weekSeconds, 1800);
    });

    test('đọc thời lượng cho dễ hiểu', () {
      expect(durationText(20), 'dưới 1 phút');
      expect(durationText(2400), '40 phút');
      expect(durationText(3600), '1 giờ');
      expect(durationText(3900), '1 giờ 5 phút');
    });

    test('dữ liệu gửi lên chỉ có thể loại và số giây, không tên bài', () {
      final day = MediaDay(day: DateTime(2026, 11, 20), topic: 'nhạc xưa', seconds: 60, plays: 1);
      // MediaDay không có trường nào cho tên bài hay mã video
      expect(day.topic, 'nhạc xưa');
      expect(summarizeMedia([day], DateTime(2026, 11, 20)).today.single.topic, 'nhạc xưa');
    });
  });

  group('cài đặt gợi ý', () {
    test('mặc định bật; tắt rồi nhớ sau khi mở lại app', () async {
      SharedPreferences.setMockInitialValues({});
      final a = ProviderContainer();
      addTearDown(a.dispose);
      expect((await a.read(vySettingsProvider.future)).remindMedia, isTrue);
      await a.read(vySettingsProvider.notifier).setRemind(media: false);
      expect(a.read(vySettingsProvider).value?.remindMedia, isFalse);
      // các nhắc khác không bị đụng
      expect(a.read(vySettingsProvider).value?.remindDose, isTrue);
    });
  });
}
