import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vg_svthm/core/router/routes.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/features/auth/domain/auth_user.dart';
import 'package:vg_svthm/features/auth/presentation/providers/auth_providers.dart';
import 'package:vg_svthm/features/entertainment/data/video_rank.dart';
import 'package:vg_svthm/features/entertainment/data/youtube_service.dart';
import 'package:vg_svthm/features/entertainment/presentation/entertainment_providers.dart';
import 'package:vg_svthm/features/entertainment/presentation/entertainment_screen.dart';

VideoItem v(String id, String title, {int? secs, String author = 'Kênh'}) => VideoItem(
  id: id,
  title: title,
  author: author,
  thumbnailUrl: '',
  duration: secs == null ? null : Duration(seconds: secs),
);

class _Fake implements VideoSearch {
  _Fake(this.byQuery);
  final Map<String, List<VideoItem>> byQuery;
  final calls = <String>[];
  final limits = <int>[];

  @override
  Future<List<VideoItem>> search(String query, {int limit = 12}) async {
    calls.add(query);
    limits.add(limit);
    return byQuery[query] ?? const [];
  }
}

void main() {
  group('hiểu loại video từ từ khoá', () {
    test('bài hát, chủ đề dài, chưa biết', () {
      expect(inferVideoKind('Nối vòng tay lớn'), VideoKind.any);
      expect(inferVideoKind('nhạc Trịnh Công Sơn'), VideoKind.song);
      expect(inferVideoKind('bài Đường chiều'), VideoKind.song);
      expect(inferVideoKind('cải lương Lệ Thủy'), VideoKind.long);
      expect(inferVideoKind('kinh Phật'), VideoKind.long);
      expect(inferVideoKind('tin tức hôm nay'), VideoKind.long);
      expect(inferVideoKind('thiền thư giãn'), VideoKind.long);
    });

    test('truy vấn chỉ nói thể loại nhạc là chung chung', () {
      expect(isGenericMusicQuery('nhạc xưa'), isTrue);
      expect(isGenericMusicQuery('nhạc vàng bolero'), isTrue);
      expect(isGenericMusicQuery('nhạc không lời'), isTrue);
      expect(isGenericMusicQuery('nhạc Trịnh Công Sơn'), isFalse);
      expect(isGenericMusicQuery('Khánh Ly'), isFalse);
    });

    test('từ khoá chung chung hiện danh sách, cụ thể thì không (cả bộ chủ đề mới)', () {
      for (final q in ['nhạc xưa', 'tin tức', 'cải lương', 'nhạc trữ tình', 'kinh Phật', 'truyện đêm khuya', 'thiền thư giãn', 'nhạc ru ngủ', 'hài kịch', 'bolero']) {
        expect(isVagueVideoQuery(q), isTrue, reason: q);
      }
      for (final q in ['Nối vòng tay lớn', 'nhạc Trịnh Công Sơn', 'Khánh Ly hát', 'cải lương Lệ Thủy Minh Vương', 'con mèo']) {
        expect(isVagueVideoQuery(q), isFalse, reason: q);
      }
    });

    test('mở rộng nhẹ từ khoá chung chung, giữ nguyên từ khoá cụ thể', () {
      expect(refineVideoQuery('tin tức'), 'tin tức hôm nay');
      expect(refineVideoQuery('Nhạc xưa'), 'nhạc xưa tuyển chọn');
      expect(refineVideoQuery('nối vòng tay lớn'), 'nối vòng tay lớn');
      expect(refineVideoQuery('cải lương Lệ Thủy'), 'cải lương Lệ Thủy');
    });

    test('yêu cầu để ngủ thì hẹn giờ tắt 30 phút, còn lại không', () {
      expect(defaultSleepMinutesFor('nhạc ru ngủ'), 30);
      expect(defaultSleepMinutesFor('nhạc để ngủ'), 30); // bỏ dấu thì "để" và "dễ" giống nhau, cả hai đều là nhu cầu ngủ
      expect(defaultSleepMinutesFor('nhạc cho dễ ngủ'), 30);
      expect(defaultSleepMinutesFor('nhạc xưa'), isNull);
    });
  });

  group('xếp hạng kết quả', () {
    test('bỏ Shorts và video quá ngắn khi nghe bài hát', () {
      final r = rankVideos([
        v('s1', 'Đường chiều #shorts', secs: 40),
        v('s2', 'Đường chiều (clip 20 giây)', secs: 20),
        v('ok', 'Đường chiều - Khánh Ly', secs: 280),
      ], 'bài Đường chiều');
      expect(r.map((e) => e.id), ['ok']);
    });

    test('bài cụ thể: bỏ bản 2 giờ tổng hợp, ưu tiên khớp tên, bản karaoke/remix xuống cuối', () {
      final r = rankVideos([
        v('karaoke', 'Đường chiều KARAOKE beat chuẩn', secs: 270),
        v('long', 'Liên khúc nhạc xưa hay nhất', secs: 7200),
        v('remix', 'Đường chiều remix DJ', secs: 240),
        v('ok', 'Đường chiều - Khánh Ly (Official)', secs: 300, author: 'Khánh Ly Official'),
      ], 'nhạc Đường chiều');
      expect(r.first.id, 'ok');
      expect(r.map((e) => e.id).contains('long'), isFalse);
      expect(r.indexWhere((e) => e.id == 'karaoke'), greaterThan(0));
    });

    test('nhạc theo thể loại: bản tuyển chọn dài đứng đầu (nghe liên tục)', () {
      final r = rankVideos([
        v('single', 'Một bài nhạc xưa', secs: 240),
        v('mix', 'Nhạc xưa tuyển chọn hay nhất', secs: 3600),
      ], 'nhạc xưa');
      expect(r.first.id, 'mix');
    });

    test('muốn karaoke thì không bị phạt', () {
      final r = rankVideos([
        v('a', 'Nhạc vàng hay', secs: 300),
        v('k', 'Karaoke nhạc vàng', secs: 280),
      ], 'karaoke nhạc vàng');
      expect(r.first.id, 'k');
    });

    test('vở diễn, phim, truyện: dài là bình thường, video 30 giây bị bỏ', () {
      final r = rankVideos([
        v('tiktok', 'Cải lương trích đoạn', secs: 30),
        v('vo', 'Cải lương Lệ Thủy - vở Tiếng trống Mê Linh', secs: 5400),
      ], 'cải lương Lệ Thủy');
      expect(r.map((e) => e.id), ['vo']);
    });

    test('trực tiếp (không rõ thời lượng): bỏ khi nghe bài hát, giữ khi tin tức/đài', () {
      expect(rankVideos([v('live', 'Nhạc xưa trực tiếp 24/7'), v('ok', 'Nhạc xưa', secs: 3000)], 'nhạc xưa').map((e) => e.id), ['ok']);
      expect(rankVideos([v('live', 'Tin tức trực tiếp')], 'tin tức').map((e) => e.id), ['live']);
    });

    test('loại trùng tên (khác nhãn kỹ thuật)', () {
      final r = rankVideos([
        v('1', 'Nối vòng tay lớn (Official MV)', secs: 250),
        v('2', 'Nối vòng tay lớn [HD]', secs: 250),
        v('3', 'Nối vòng tay lớn 4K', secs: 250),
      ], 'nối vòng tay lớn');
      expect(r.length, lessThanOrEqualTo(2));
      expect(r.map((e) => videoTitleKey(e.title)).toSet().length, r.length);
    });

    test('lọc quá tay thì lùi về danh sách chỉ bỏ Shorts, không trả rỗng', () {
      final r = rankVideos([v('a', 'Karaoke gì đó', secs: 5), v('b', 'Cái khác #shorts', secs: 5)], 'nhạc xưa');
      expect(r, isNotEmpty);
    });

    test('giới hạn số lượng', () {
      final items = [for (var i = 0; i < 15; i++) v('$i', 'Bài số $i khác nhau hẳn', secs: 240)];
      expect(rankVideos(items, 'nhạc', limit: 5).length, 5);
    });
  });

  group('tìm và xếp hạng', () {
    test('RankedVideoSearch xin 20 kết quả với từ khoá đã mở rộng, rồi cắt về số cần', () async {
      final inner = _Fake({
        'tin tức hôm nay': [for (var i = 0; i < 20; i++) v('t$i', 'Bản tin số $i', secs: 900)],
      });
      final out = await RankedVideoSearch(inner).search('tin tức', limit: 5);
      expect(inner.calls, ['tin tức hôm nay']);
      expect(inner.limits, [20]);
      expect(out.length, 5);
    });

    test('hàng đợi tự bổ sung: bỏ video đã có, thử cách nói khác khi cùng kết quả', () async {
      final a = v('a', 'Bài một', secs: 200);
      final b = v('b', 'Bài hai', secs: 200);
      final c = v('c', 'Bài ba', secs: 200);
      final inner = _Fake({
        'nhạc xưa': [a, b],
        'nhạc xưa hay nhất': [b, c],
      });
      final r1 = await nextBatch(search: inner, topic: 'nhạc xưa', have: {'a', 'b'});
      expect(r1.items.map((e) => e.id), ['c']);
      expect(r1.step, 2); // đã dùng tới cách nói thứ hai
      expect(inner.calls, ['nhạc xưa', 'nhạc xưa hay nhất']);
    });

    test('hàng đợi: hết cách nói thì trả rỗng và không tìm nữa', () async {
      final inner = _Fake({});
      final r = await nextBatch(search: inner, topic: 'nhạc xưa', have: {'a'});
      expect(r.items, isEmpty);
      expect(r.step, 4);
      final calls = inner.calls.length;
      final r2 = await nextBatch(search: inner, topic: 'nhạc xưa', have: {'a'}, step: r.step);
      expect(r2.items, isEmpty);
      expect(inner.calls.length, calls);
    });

    test('hàng đợi: loại video trùng tên với bài đã có', () async {
      final inner = _Fake({
        'nhạc xưa': [v('x', 'Bài một (Official MV)', secs: 200), v('y', 'Bài mới', secs: 200)],
      });
      final r = await nextBatch(
        search: inner,
        topic: 'nhạc xưa',
        have: {'a'},
        haveTitles: {videoTitleKey('Bài một')},
      );
      expect(r.items.map((e) => e.id), ['y']);
    });
  });

  group('Giải trí: Vy đánh số mà người dùng im lặng', () {
    Widget app(_Fake fake, ProviderContainer? c) {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const EntertainmentScreen()),
          GoRoute(
            path: Routes.player,
            builder: (_, s) => Scaffold(body: Text('PLAYER ${(s.extra as VideoItem).id}')),
          ),
        ],
      );
      return UncontrolledProviderScope(
        container: c!,
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      );
    }

    ProviderContainer make(_Fake fake) => ProviderContainer(
      overrides: [
        currentUserProvider.overrideWithValue(const AuthUser(id: 'me', username: 'minh', role: AppRole.elder)),
        videoSearchProvider.overrideWithValue(fake),
      ],
    );

    testWidgets('sau 10 giây tự mở video số 1, nhớ chủ đề để nối bài', (t) async {
      final fake = _Fake({
        'nhạc xưa': [v('first', 'Bài đầu', secs: 240), v('second', 'Bài hai', secs: 240)],
      });
      final c = make(fake);
      addTearDown(c.dispose);
      t.view.physicalSize = const Size(900, 3000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(app(fake, c));
      c.read(videoQueryProvider.notifier).set('nhạc xưa');
      await t.pumpAndSettle();
      c.read(videoMarksProvider.notifier).set(true);
      await t.pump();
      await t.pump(const Duration(seconds: 9));
      expect(find.text('PLAYER first'), findsNothing, reason: 'chưa đủ 10 giây');
      await t.pump(const Duration(seconds: 2));
      await t.pumpAndSettle();
      expect(find.text('PLAYER first'), findsOneWidget);
      expect(c.read(videoTopicProvider), 'nhạc xưa');
      expect(c.read(videoQueueProvider).map((e) => e.id), ['first', 'second']);
      expect(c.read(videoMarksProvider), isFalse);
    });

    testWidgets('người dùng tự chọn trước 10 giây thì không mở thêm lần nữa', (t) async {
      final fake = _Fake({
        'nhạc xưa': [v('first', 'Bài đầu', secs: 240), v('second', 'Bài hai', secs: 240)],
      });
      final c = make(fake);
      addTearDown(c.dispose);
      t.view.physicalSize = const Size(900, 3000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(app(fake, c));
      c.read(videoQueryProvider.notifier).set('nhạc xưa');
      await t.pumpAndSettle();
      c.read(videoMarksProvider.notifier).set(true);
      await t.pump();
      await t.tap(find.text('Bài hai'));
      await t.pumpAndSettle();
      expect(find.text('PLAYER second'), findsOneWidget);
      await t.pump(const Duration(seconds: 15));
      expect(find.text('PLAYER first'), findsNothing);
    });

    testWidgets('không đánh số thì không tự mở gì', (t) async {
      final fake = _Fake({
        'nhạc xưa': [v('first', 'Bài đầu', secs: 240)],
      });
      final c = make(fake);
      addTearDown(c.dispose);
      t.view.physicalSize = const Size(900, 3000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(app(fake, c));
      c.read(videoQueryProvider.notifier).set('nhạc xưa');
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 30));
      expect(find.textContaining('PLAYER'), findsNothing);
    });

    testWidgets('nghe để ngủ: chọn từ danh sách thì đặt sẵn hẹn giờ 30 phút', (t) async {
      final fake = _Fake({
        'nhạc ru ngủ': [v('a', 'Nhạc ru ngủ nhẹ', secs: 3600)],
      });
      final c = make(fake);
      addTearDown(c.dispose);
      t.view.physicalSize = const Size(900, 3000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(app(fake, c));
      c.read(videoQueryProvider.notifier).set('nhạc ru ngủ');
      await t.pumpAndSettle();
      await t.tap(find.text('Nhạc ru ngủ nhẹ'));
      await t.pumpAndSettle();
      expect(c.read(playerStartSleepProvider), 30);
    });
  });
}
