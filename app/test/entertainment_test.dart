import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/features/auth/domain/auth_user.dart';
import 'package:vg_svthm/features/auth/presentation/providers/auth_providers.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/features/entertainment/data/youtube_service.dart';
import 'package:vg_svthm/features/entertainment/presentation/entertainment_providers.dart';
import 'package:vg_svthm/features/entertainment/presentation/entertainment_screen.dart';

class FakeSearch implements VideoSearch {
  final queries = <String>[];

  @override
  Future<List<VideoItem>> search(String query, {int limit = 12}) async {
    queries.add(query);
    return const [
      VideoItem(id: 'abc', title: 'Nối vòng tay lớn', author: 'Kênh A', thumbnailUrl: '', duration: Duration(minutes: 4, seconds: 5)),
    ];
  }
}

class _Empty implements VideoSearch {
  _Empty(this.onCall);
  final void Function() onCall;

  @override
  Future<List<VideoItem>> search(String query, {int limit = 12}) async {
    onCall();
    return const [];
  }
}

void main() {
  test('từ khoá chung chung và cụ thể', () {
    expect(isVagueVideoQuery('nhạc xưa'), isTrue);
    expect(isVagueVideoQuery('tin tức'), isTrue);
    expect(isVagueVideoQuery('cải lương'), isTrue);
    expect(isVagueVideoQuery('Nối vòng tay lớn'), isFalse);
    expect(isVagueVideoQuery('nhạc Trịnh Công Sơn'), isFalse);
  });

  test('CachedVideoSearch: cùng từ khoá chỉ tìm một lần; nhiều hơn thì tìm lại; hết hạn thì tìm lại', () async {
    final fake = FakeSearch();
    var now = DateTime(2026, 11, 24, 9);
    final s = CachedVideoSearch(fake, ttl: const Duration(minutes: 10), now: () => now);
    await s.search('Nhạc  xưa');
    await s.search('nhạc xưa');
    await s.search('nhạc xưa', limit: 5); // ít hơn: dùng lại
    expect(fake.queries.length, 1);
    await s.search('nhạc xưa', limit: 20); // nhiều hơn: phải tìm lại
    expect(fake.queries.length, 2);
    now = now.add(const Duration(minutes: 11));
    await s.search('nhạc xưa', limit: 20);
    expect(fake.queries.length, 3);
  });

  test('CachedVideoSearch: kết quả rỗng không bị nhớ', () async {
    var calls = 0;
    final s = CachedVideoSearch(_Empty(() => calls++));
    await s.search('abc');
    await s.search('abc');
    expect(calls, 2);
  });

  test('cleanVideoTitle: bỏ emoji, #thẻ, nhãn kỹ thuật; giữ tên người trong ngoặc; cắt ở ranh giới từ', () {
    expect(cleanVideoTitle('🎵 Đường chiều (Official MV 4K) #nhacxua #shorts'), 'Đường chiều');
    expect(cleanVideoTitle('Nối vòng tay lớn [Lyrics] | Nhạc Cách Mạng'), 'Nối vòng tay lớn - Nhạc Cách Mạng');
    expect(cleanVideoTitle('Cải lương Tiếng trống Mê Linh (Lệ Thủy, Minh Vương)'), 'Cải lương Tiếng trống Mê Linh (Lệ Thủy, Minh Vương)');
    expect(cleanVideoTitle('#shorts'), '#shorts'); // chẳng còn gì thì giữ nguyên, không đọc rỗng
    final long = cleanVideoTitle('Liên khúc nhạc vàng bolero trữ tình hay nhất mọi thời đại chọn lọc 2024 không quảng cáo');
    expect(long.length, lessThanOrEqualTo(61));
    expect(long.endsWith('…'), isTrue);
    expect(long.contains('  '), isFalse);
  });

  test('nhãn thời lượng', () {
    const v = VideoItem(id: 'a', title: 't', author: 'x', thumbnailUrl: '', duration: Duration(hours: 1, minutes: 2, seconds: 10));
    expect(v.durationLabel, '1:02:10');
    expect(const VideoItem(id: 'a', title: 't', author: 'x', thumbnailUrl: '').durationLabel, '');
  });

  testWidgets('gõ từ khoá thì hiện danh sách video', (t) async {
    final fake = FakeSearch();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
            currentUserProvider.overrideWithValue(const AuthUser(id: 'me', username: 'minh', role: AppRole.family)),videoSearchProvider.overrideWithValue(fake)],
        child: MaterialApp(theme: AppTheme.light, home: const EntertainmentScreen()),
      ),
    );
    expect(find.text('Giải trí'), findsOneWidget);
    await t.scrollUntilVisible(find.byKey(const Key('video-search')), 300, scrollable: find.byType(Scrollable).first);
    await t.enterText(find.byKey(const Key('video-search')), 'nối vòng tay lớn');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
    expect(fake.queries, ['nối vòng tay lớn']);
    expect(find.text('Nối vòng tay lớn'), findsOneWidget);
    expect(find.text('4:05'), findsOneWidget);
  });

  testWidgets('chạm một mục gợi ý là tìm ngay, có nút chọn mục khác', (t) async {
    final fake = FakeSearch();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
            currentUserProvider.overrideWithValue(const AuthUser(id: 'me', username: 'minh', role: AppRole.family)),videoSearchProvider.overrideWithValue(fake)],
        child: MaterialApp(theme: AppTheme.light, home: const EntertainmentScreen()),
      ),
    );
    await t.tap(find.text('Cải lương'));
    await t.pumpAndSettle();
    expect(fake.queries, ['cải lương']);
    await t.tap(find.bySemanticsLabel('Chọn mục khác'));
    await t.pumpAndSettle();
    expect(find.text('Nhạc xưa'), findsOneWidget);
  });
}
