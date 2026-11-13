import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
  test('từ khoá chung chung và cụ thể', () {
    expect(isVagueVideoQuery('nhạc xưa'), isTrue);
    expect(isVagueVideoQuery('tin tức'), isTrue);
    expect(isVagueVideoQuery('cải lương'), isTrue);
    expect(isVagueVideoQuery('Nối vòng tay lớn'), isFalse);
    expect(isVagueVideoQuery('nhạc Trịnh Công Sơn'), isFalse);
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
        overrides: [videoSearchProvider.overrideWithValue(fake)],
        child: MaterialApp(theme: AppTheme.light, home: const EntertainmentScreen()),
      ),
    );
    expect(find.text('Giải trí'), findsOneWidget);
    await t.enterText(find.byKey(const Key('video-search')), 'nối vòng tay lớn');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
    expect(fake.queries, ['nối vòng tay lớn']);
    expect(find.text('Nối vòng tay lớn'), findsOneWidget);
    expect(find.text('4:05'), findsOneWidget);
  });
}
