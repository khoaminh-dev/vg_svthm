import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vg_svthm/core/router/app_router.dart';
import 'package:vg_svthm/core/router/routes.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/features/auth/domain/auth_user.dart';
import 'package:vg_svthm/features/auth/presentation/providers/auth_providers.dart';
import 'package:vg_svthm/features/entertainment/data/media_curation.dart';
import 'package:vg_svthm/features/entertainment/data/media_memory.dart';
import 'package:vg_svthm/features/entertainment/data/video_rank.dart';
import 'package:vg_svthm/features/entertainment/data/youtube_service.dart';
import 'package:vg_svthm/features/entertainment/presentation/entertainment_providers.dart';
import 'package:vg_svthm/features/entertainment/presentation/entertainment_screen.dart';
import 'package:vg_svthm/features/voice/core/vy_settings.dart';
import 'package:vg_svthm/features/voice/data/voice_actions.dart';
import 'package:vg_svthm/features/voice/domain/voice_models.dart';

VideoItem v(String id, String title, {int secs = 240, String author = 'Kênh'}) =>
    VideoItem(id: id, title: title, author: author, thumbnailUrl: '', duration: Duration(seconds: secs));

final t0 = DateTime(2026, 11, 20, 8, 30); // sáng
DateTime days(int n, {int hour = 8}) => DateTime(2026, 11, 20 - n, hour);

void main() {
  group('trí nhớ thuần', () {
    test('ghi lượt nghe: bài mới ở đầu, nghe lại thì cộng lượt và đưa lên đầu', () {
      var m = const MediaMemory();
      m = m.recordPlay(v('a', 'Bài A'), 'nhạc xưa', t0);
      m = m.recordPlay(v('b', 'Bài B'), 'cải lương', t0.add(const Duration(minutes: 5)));
      m = m.recordPlay(v('a', 'Bài A'), '', t0.add(const Duration(minutes: 9)));
      expect(m.entries.map((e) => e.id), ['a', 'b']);
      expect(m.entries.first.count, 2);
      expect(m.entries.first.topic, 'nhạc xưa', reason: 'chủ đề trống thì giữ chủ đề cũ');
    });

    test('bài đang xem dở: dài ≥ 15 phút, đã xem ≥ 1 phút, còn ≥ 90 giây, chưa xong, trong 14 ngày', () {
      MediaMemory withProgress(int dur, int pos, {bool done = false, DateTime? at}) {
        var m = const MediaMemory().recordPlay(v('x', 'Tập 5', secs: dur), 'phim bộ', at ?? t0);
        return m.updateProgress('x', progressSec: pos, durationSec: dur, completed: done);
      }

      expect(withProgress(3000, 600).resumable(t0)?.id, 'x');
      expect(withProgress(300, 100).resumable(t0), isNull, reason: 'bài ngắn không "xem dở"');
      expect(withProgress(3000, 30).resumable(t0), isNull, reason: 'mới xem 30 giây');
      expect(withProgress(3000, 2950).resumable(t0), isNull, reason: 'gần hết bài');
      expect(withProgress(3000, 600, done: true).resumable(t0), isNull);
      expect(withProgress(3000, 600, at: days(20)).resumable(t0), isNull, reason: 'quá 14 ngày');
    });

    test('chủ đề hay nghe: cần ≥ 2 lượt, cùng khung giờ tính gấp đôi, quá 45 ngày bỏ qua, bài bị chê không tính', () {
      var m = const MediaMemory();
      // cải lương: 3 lượt buổi tối; nhạc xưa: 2 lượt buổi sáng; tin tức: 1 lượt
      for (var i = 0; i < 3; i++) {
        m = m.recordPlay(v('cl$i', 'Cải lương $i'), 'cải lương', days(i + 1, hour: 20));
      }
      for (var i = 0; i < 2; i++) {
        m = m.recordPlay(v('nx$i', 'Nhạc xưa $i'), 'nhạc xưa', days(i + 1, hour: 8));
      }
      m = m.recordPlay(v('tt', 'Tin'), 'tin tức', days(1, hour: 8));
      // buổi sáng: nhạc xưa (2×2=4) thắng cải lương (3×1=3); tin tức chưa đủ 2 lượt
      expect(m.topTopics(t0), ['nhạc xưa', 'cải lương']);
      // buổi tối: cải lương (3×2=6) thắng
      expect(m.topTopics(DateTime(2026, 11, 20, 20, 0)).first, 'cải lương');
      expect(m.suggestedTopic(t0), 'nhạc xưa');
      // chưa nghe gì: không có gợi ý
      expect(const MediaMemory().suggestedTopic(t0), isNull);
      // quá 45 ngày: bỏ
      final old = const MediaMemory()
          .recordPlay(v('o1', 'Cũ 1'), 'bolero', days(60))
          .recordPlay(v('o2', 'Cũ 2'), 'bolero', days(61));
      expect(old.topTopics(t0), isEmpty);
      // bài bị chê không góp điểm
      final disliked = m.setDisliked('nx0', true).setDisliked('nx1', true);
      expect(disliked.topTopics(t0).contains('nhạc xưa'), isFalse);
    });

    test('thích và không thích loại trừ nhau; danh sách thích, bài vừa nghe bỏ qua bài bị chê', () {
      var m = const MediaMemory()
          .recordPlay(v('a', 'A'), 'nhạc xưa', t0)
          .recordPlay(v('b', 'B'), 'nhạc xưa', t0.add(const Duration(minutes: 1)));
      m = m.setLiked('a', true);
      expect(m.likedIds, {'a'});
      m = m.setDisliked('a', true);
      expect(m.likedIds, isEmpty);
      expect(m.dislikedIds, {'a'});
      m = m.setDisliked('b', true);
      expect(m.last, isNull, reason: 'mọi bài gần đây đều bị chê');
      m = m.setLiked('a', true);
      expect(m.liked.map((e) => e.id), ['a']);
      expect(m.dislikedIds, {'b'});
    });

    test('quá 150 mục: bỏ bài cũ nhất nhưng giữ bài thích và bài đã chê', () {
      var m = const MediaMemory(maxEntries: 5);
      m = m.recordPlay(v('liked', 'Bài thích'), 'x', t0).setLiked('liked', true);
      m = m.recordPlay(v('bad', 'Bài chê'), 'x', t0).setDisliked('bad', true);
      for (var i = 0; i < 10; i++) {
        m = m.recordPlay(v('n$i', 'Bài $i'), 'x', t0.add(Duration(minutes: i + 1)));
      }
      expect(m.entries.length, 5);
      expect(m.likedIds, {'liked'});
      expect(m.dislikedIds, {'bad'});
    });

    test('lưu rồi đọc lại đủ; dữ liệu hỏng thì coi như trống', () {
      var m = const MediaMemory().recordPlay(v('a', 'Bài A', secs: 3000), 'phim bộ', t0);
      m = m.updateProgress('a', progressSec: 700, durationSec: 3000).setLiked('a', true);
      final back = MediaMemory.decode(m.encode());
      expect(back.entries.single.id, 'a');
      expect(back.entries.single.progressSec, 700);
      expect(back.entries.single.liked, isTrue);
      expect(back.entries.single.topic, 'phim bộ');
      expect(MediaMemory.decode('không phải json').isEmpty, isTrue);
      expect(MediaMemory.decode('{"a":1}').isEmpty, isTrue);
      expect(MediaMemory.decode(null).isEmpty, isTrue);
      expect(MediaMemory.decode('[{"id":""},5,null,{"id":"ok","title":"t"}]').entries.single.id, 'ok');
    });

    test('tóm tắt thói quen gửi lên Vy chỉ có chủ đề và tên bài đã làm sạch', () {
      var m = const MediaMemory()
          .recordPlay(v('b', 'Bài B'), 'nhạc xưa', days(2))
          .recordPlay(v('a', '🎵 Đường chiều (Official MV) #shorts'), 'nhạc xưa', days(1));
      final h = m.habitJson(t0);
      expect(h['top'], 'nhạc xưa');
      expect(h['topics'], ['nhạc xưa']);
      expect(h['last'], 'Đường chiều');
      expect(h['resume'], '');
      expect(h.keys.toSet(), {'top', 'topics', 'resume', 'last'});
    });
  });

  group('lọc nội dung sức khoẻ và tin tức', () {
    test('nhận chủ đề sức khoẻ và tin tức', () {
      expect(isHealthQuery('bài tập dưỡng sinh người lớn tuổi'), isTrue);
      expect(isHealthQuery('yoga cho người cao tuổi'), isTrue);
      expect(isHealthQuery('nhạc xưa'), isFalse);
      expect(isNewsQuery('tin tức hôm nay'), isTrue);
      expect(isNewsQuery('hài kịch'), isFalse);
    });

    test('video hứa chữa khỏi / khuyên bỏ thuốc bị loại; nguồn bệnh viện được ưu tiên', () {
      final r = rankVideos([
        v('bad1', 'Cách hạ huyết áp ngay không cần uống thuốc, bí quyết bác sĩ không nói', secs: 600),
        v('bad2', 'Bỏ thuốc huyết áp, chữa khỏi hoàn toàn tại nhà', secs: 600),
        v('ok1', 'Bài tập dưỡng sinh nhẹ nhàng buổi sáng', secs: 900, author: 'Kênh Sống Vui'),
        v('good', 'Bài tập dưỡng sinh cho người cao tuổi', secs: 900, author: 'Bệnh viện Lão khoa Trung ương'),
      ], 'bài tập dưỡng sinh người lớn tuổi');
      expect(r.first.id, 'good');
      expect(r.map((e) => e.id).contains('bad1'), isFalse);
      expect(r.map((e) => e.id).contains('bad2'), isFalse);
      expect(r.map((e) => e.id).contains('ok1'), isTrue);
    });

    test('toàn video nguy hiểm: trả rỗng chứ không lùi về video nguy hiểm', () {
      final r = rankVideos([
        v('bad1', 'Bỏ thuốc huyết áp, chữa khỏi hoàn toàn', secs: 600),
        v('bad2', 'Thuốc tiên hạ huyết áp thần kỳ', secs: 600),
      ], 'bài tập dưỡng sinh');
      expect(r, isEmpty);
    });

    test('chủ đề không phải sức khoẻ thì không bị rào này', () {
      final r = rankVideos([v('a', 'Mẹo hay nấu ăn bí quyết gia truyền', secs: 600)], 'hài kịch');
      expect(r.single.id, 'a');
    });

    test('tin tức: nguồn đài truyền hình/báo lớn đứng trước video giật gân', () {
      final r = rankVideos([
        v('a', 'Tin tức mới nhất hôm nay không thể tin nổi', secs: 600, author: 'Tin Nóng 24h'),
        v('b', 'Bản tin 19 giờ hôm nay', secs: 1500, author: 'VTV24'),
      ], 'tin tức hôm nay');
      expect(r.first.id, 'b');
    });

    test('bài đã chê không bao giờ hiện lại, kể cả khi lọc quá tay; bài đã khen lên trước', () {
      final items = [
        v('bad', 'Đường chiều - Khánh Ly', secs: 280),
        v('b', 'Đường chiều - Khánh Ly bản khác', secs: 290),
        v('c', 'Một bài khác hẳn', secs: 250),
      ];
      final ranked = rankVideos(items, 'nhạc xưa', excluded: {'bad'}, liked: {'c'});
      expect(ranked.map((e) => e.id).contains('bad'), isFalse);
      expect(ranked.first.id, 'c');
      final only = rankVideos([v('bad', 'x', secs: 5)], 'nhạc xưa', excluded: {'bad'});
      expect(only, isEmpty);
    });
  });

  group('lưu trên máy theo tài khoản', () {
    ProviderContainer make({String uid = 'u1', bool remember = true}) {
      final c = ProviderContainer(overrides: [
        currentUserProvider.overrideWithValue(AuthUser(id: uid, username: 'minh', role: AppRole.elder)),
        vySettingsProvider.overrideWith(() => _Settings(VySettings(rememberMedia: remember))),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('ghi rồi mở lại app vẫn còn; tài khoản khác không thấy', () async {
      SharedPreferences.setMockInitialValues({});
      final a = make();
      a.read(vySettingsProvider);
      await Future<void>.delayed(Duration.zero);
      a.read(mediaMemoryProvider.notifier).play(v('a', 'Bài A'), 'nhạc xưa');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(a.read(mediaMemoryProvider).entries.single.id, 'a');

      final b = make(); // "mở lại app": bộ chứa mới, cùng tài khoản
      b.read(vySettingsProvider);
      b.read(mediaMemoryProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(b.read(mediaMemoryProvider).entries.single.id, 'a');

      final other = make(uid: 'u2');
      other.read(vySettingsProvider);
      other.read(mediaMemoryProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(other.read(mediaMemoryProvider).isEmpty, isTrue);
    });

    test('tắt "Nhớ những gì tôi đã nghe": không ghi gì và không gửi thói quen lên Vy', () async {
      SharedPreferences.setMockInitialValues({});
      final c = make(remember: false);
      c.read(vySettingsProvider);
      await Future<void>.delayed(Duration.zero);
      final n = c.read(mediaMemoryProvider.notifier);
      n.play(v('a', 'Bài A'), 'nhạc xưa');
      n.play(v('a', 'Bài A'), 'nhạc xưa');
      expect(c.read(mediaMemoryProvider).isEmpty, isTrue);
      expect(n.habit(), isEmpty);
    });

    test('xoá lịch sử: sạch cả trên máy lẫn trong bộ nhớ', () async {
      SharedPreferences.setMockInitialValues({});
      final a = make();
      a.read(vySettingsProvider);
      await Future<void>.delayed(Duration.zero);
      final n = a.read(mediaMemoryProvider.notifier);
      n.play(v('a', 'Bài A'), 'nhạc xưa');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await n.clear();
      expect(a.read(mediaMemoryProvider).isEmpty, isTrue);
      final b = make();
      b.read(vySettingsProvider);
      b.read(mediaMemoryProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(b.read(mediaMemoryProvider).isEmpty, isTrue);
    });
  });

  test('cài đặt "Nhớ những gì tôi đã nghe": mặc định bật, tắt rồi vẫn nhớ sau khi mở lại app', () async {
    SharedPreferences.setMockInitialValues({});
    final a = ProviderContainer();
    addTearDown(a.dispose);
    expect((await a.read(vySettingsProvider.future)).rememberMedia, isTrue);
    await a.read(vySettingsProvider.notifier).setRememberMedia(false);
    final b = ProviderContainer();
    addTearDown(b.dispose);
    expect((await b.read(vySettingsProvider.future)).rememberMedia, isFalse);
  });

  group('Vy nhớ lại bằng giọng', () {
    GoRouter router() => GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const SizedBox()),
      GoRoute(path: Routes.entertainment, builder: (_, _) => const SizedBox()),
      GoRoute(path: Routes.player, builder: (_, _) => const SizedBox()),
    ]);

    ProviderContainer make(MediaMemory mem, {List<VideoItem> found = const []}) {
      final c = ProviderContainer(overrides: [
        routerProvider.overrideWithValue(router()),
        mediaMemoryProvider.overrideWith(() => _SeededMemory(mem)),
        vySettingsProvider.overrideWith(() => _Settings(const VySettings())),
        videoSearchProvider.overrideWithValue(_Search(found)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<String?> say(ProviderContainer c, String content) =>
        c.read(voiceActionsProvider).execute(VoiceTask(intent: 'play_video', slots: {'content': content}), const [], 'bác');

    final longVideo = v('tap5', 'Tây Du Ký tập 5 (Full HD)', secs: 2700);

    test('@last: chưa nghe gì thì nói thật và hỏi muốn nghe gì', () async {
      final c = make(const MediaMemory());
      expect(await say(c, '@last'), contains('chưa thấy bác nghe gì'));
      expect(c.read(videoQueueProvider), isEmpty);
    });

    test('@last: mở lại đúng bài vừa nghe, giữ chủ đề để nối bài sau, đọc tên đã làm sạch', () async {
      final mem = const MediaMemory().recordPlay(v('a', '🎵 Đường chiều (Official MV) #shorts'), 'nhạc xưa', DateTime.now());
      final c = make(mem);
      expect(await say(c, '@last'), 'Dạ, con mở lại Đường chiều ạ.');
      expect(c.read(videoQueueProvider).single.id, 'a');
      expect(c.read(videoTopicProvider), 'nhạc xưa');
      expect(c.read(playerStartAtProvider), isNull);
    });

    test('@last: bài dài đang dở thì mở tiếp đúng chỗ', () async {
      var mem = const MediaMemory().recordPlay(longVideo, 'phim bộ', DateTime.now());
      mem = mem.updateProgress('tap5', progressSec: 900, durationSec: 2700);
      final c = make(mem);
      final s = await say(c, '@last');
      expect(s, contains('mở tiếp Tây Du Ký tập 5'));
      expect(c.read(playerStartAtProvider), 900);
    });

    test('@resume: có bài dở thì mở tiếp từ chỗ dở; không có thì nói thật', () async {
      var mem = const MediaMemory().recordPlay(longVideo, 'phim bộ', DateTime.now());
      mem = mem.updateProgress('tap5', progressSec: 1200, durationSec: 2700);
      final c = make(mem);
      expect(await say(c, '@resume'), contains('xem dở'));
      expect(c.read(playerStartAtProvider), 1200);
      final none = make(const MediaMemory().recordPlay(v('a', 'Bài ngắn'), 'x', DateTime.now()));
      expect(await say(none, '@resume'), contains('không thấy bài nào'));
      expect(none.read(playerStartAtProvider), isNull);
    });

    test('@favorite: mở danh sách bài đã thích; chưa có thì hướng dẫn nói "bài này hay"', () async {
      final mem = const MediaMemory()
          .recordPlay(v('a', 'Bài A'), 'nhạc xưa', DateTime.now())
          .recordPlay(v('b', 'Bài B'), 'nhạc xưa', DateTime.now())
          .setLiked('a', true)
          .setLiked('b', true);
      final c = make(mem);
      expect(await say(c, '@favorite'), contains('bài bác thích'));
      expect(c.read(videoQueueProvider).map((e) => e.id).toSet(), {'a', 'b'});
      final none = make(const MediaMemory());
      expect(await say(none, '@favorite'), contains('bài này hay'));
    });

    test('@habit:<chủ đề>: Vy tìm đúng chủ đề thói quen, nói rõ vì sao chọn, phát luôn không hỏi', () async {
      var mem = const MediaMemory();
      for (var i = 0; i < 3; i++) {
        mem = mem.recordPlay(v('n$i', 'Nhạc $i'), 'nhạc xưa', DateTime.now());
      }
      final c = make(mem, found: [v('f1', 'Nhạc xưa tuyển chọn', secs: 3600), v('f2', 'Bài 2')]);
      final s = await say(c, '@habit');
      expect(s, 'Dạ, giờ này bác hay nghe nhạc xưa, con mở Nhạc xưa tuyển chọn ạ.');
      expect(c.read(videoQueueProvider).map((e) => e.id), ['f1', 'f2']);
      expect(c.read(videoTopicProvider), 'nhạc xưa');
    });

    test('@habit chưa có thói quen: hỏi lại, không mở bừa', () async {
      final c = make(const MediaMemory());
      expect(await say(c, '@habit'), 'Dạ, bác muốn nghe gì ạ?');
    });

    test('nghe để ngủ từ lịch sử: tự hẹn giờ tắt', () async {
      final mem = const MediaMemory().recordPlay(v('z', 'Nhạc ru ngủ nhẹ', secs: 3600), 'nhạc ru ngủ', DateTime.now());
      final c = make(mem);
      await say(c, '@last');
      expect(c.read(playerStartSleepProvider), 30);
    });
  });

  group('Vy nhận lời khen/chê khi đang phát', () {
    ProviderContainer make({bool remember = true}) {
      final c = ProviderContainer(overrides: [
        routerProvider.overrideWithValue(GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())])),
        mediaMemoryProvider.overrideWith(() => _SeededMemory(const MediaMemory())),
        vySettingsProvider.overrideWith(() => _Settings(VySettings(rememberMedia: remember))),
      ]);
      addTearDown(c.dispose);
      c.read(playerOpenProvider.notifier).set(true);
      return c;
    }

    Future<String?> ctl(ProviderContainer c, String a) =>
        c.read(voiceActionsProvider).execute(VoiceTask(intent: 'video_control', slots: {'content': a}), const [], 'bác');

    test('"bài này hay" gửi lệnh nhớ bài và Vy nói đã nhớ', () async {
      final c = make();
      expect(await ctl(c, 'like'), contains('con nhớ bài này'));
      expect(c.read(playerCommandProvider)?.action, PlayerAction.like);
    });

    test('"không thích bài này" gửi lệnh bỏ bài và sang bài khác', () async {
      final c = make();
      expect(await ctl(c, 'dislike'), contains('bỏ bài này'));
      expect(c.read(playerCommandProvider)?.action, PlayerAction.dislike);
    });

    test('"đừng gợi ý nữa": tắt gợi ý chủ động, nói được cả khi chưa phát video', () async {
      SharedPreferences.setMockInitialValues({});
      final c = make();
      c.read(playerOpenProvider.notifier).set(false);
      await c.read(vySettingsProvider.future);
      final say = await ctl(c, 'suggest_off');
      expect(say, contains('không tự gợi ý'));
      expect(c.read(vySettingsProvider).value?.remindMedia, isFalse);
      expect(c.read(playerCommandProvider), isNull, reason: 'không gửi lệnh gì cho trình phát');
    });

    test('đã tắt chế độ nhớ thì nói thật là chưa lưu được', () async {
      final c = make(remember: false);
      await c.read(vySettingsProvider.future);
      expect(await ctl(c, 'like'), contains('đang tắt chế độ nhớ'));
    });
  });

  group('Giải trí: thẻ xem tiếp / nghe lại', () {
    ProviderContainer make(MediaMemory mem, {bool remember = true}) {
      final c = ProviderContainer(overrides: [
        currentUserProvider.overrideWithValue(const AuthUser(id: 'me', username: 'minh', role: AppRole.elder)),
        mediaMemoryProvider.overrideWith(() => _SeededMemory(mem)),
        vySettingsProvider.overrideWith(() => _Settings(VySettings(rememberMedia: remember))),
        videoSearchProvider.overrideWithValue(_Search(const [])),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Widget app(ProviderContainer c) {
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const EntertainmentScreen()),
        GoRoute(path: Routes.player, builder: (_, s) => Scaffold(body: Text('PLAYER ${(s.extra as VideoItem).id}'))),
      ]);
      return UncontrolledProviderScope(
        container: c,
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      );
    }

    testWidgets('bài dài đang dở: hiện "Xem tiếp", chạm là phát từ đúng chỗ', (t) async {
      t.view.physicalSize = const Size(900, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      var mem = const MediaMemory().recordPlay(v('tap5', 'Tây Du Ký tập 5', secs: 2700), 'phim bộ', DateTime.now());
      mem = mem.updateProgress('tap5', progressSec: 900, durationSec: 2700);
      final c = make(mem);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('ent-resume')), findsOneWidget);
      expect(find.text('Xem tiếp'), findsOneWidget);
      await t.tap(find.byKey(const Key('ent-resume')));
      await t.pumpAndSettle();
      expect(find.text('PLAYER tap5'), findsOneWidget);
      expect(c.read(playerStartAtProvider), 900);
      expect(c.read(videoTopicProvider), 'phim bộ');
    });

    testWidgets('bài ngắn vừa nghe: hiện "Nghe lại", chạm là mở lại', (t) async {
      t.view.physicalSize = const Size(900, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final mem = const MediaMemory().recordPlay(v('a', 'Đường chiều'), 'nhạc xưa', DateTime.now());
      final c = make(mem);
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('ent-last')), findsOneWidget);
      expect(find.text('Nghe lại'), findsOneWidget);
      await t.tap(find.byKey(const Key('ent-last')));
      await t.pumpAndSettle();
      expect(find.text('PLAYER a'), findsOneWidget);
      expect(c.read(playerStartAtProvider), isNull, reason: 'bài ngắn nghe lại từ đầu');
    });

    testWidgets('tắt chế độ nhớ: không hiện thẻ nào', (t) async {
      final mem = const MediaMemory().recordPlay(v('a', 'Đường chiều'), 'nhạc xưa', DateTime.now());
      final off = make(mem, remember: false);
      await t.pumpWidget(app(off));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('ent-last')), findsNothing);
      expect(find.byKey(const Key('ent-resume')), findsNothing);
    });

    testWidgets('chưa nghe gì: không có thẻ nào', (t) async {
      final c = make(const MediaMemory());
      await t.pumpWidget(app(c));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('ent-last')), findsNothing);
      expect(find.byKey(const Key('ent-resume')), findsNothing);
    });
  });
}

class _Settings extends VySettingsNotifier {
  _Settings(this.s);
  final VySettings s;

  @override
  Future<VySettings> build() async => s;
}

class _SeededMemory extends MediaMemoryNotifier {
  _SeededMemory(this.seed);
  final MediaMemory seed;

  @override
  MediaMemory build() => seed;
}

class _Search implements VideoSearch {
  _Search(this.items);
  final List<VideoItem> items;

  @override
  Future<List<VideoItem>> search(String query, {int limit = 12}) async => items;
}
