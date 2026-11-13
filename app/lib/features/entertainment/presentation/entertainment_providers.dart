import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../data/youtube_service.dart';

final videoSearchProvider = Provider<VideoSearch>(
  (ref) => ApiVideoSearch(
    accessToken: () => ref.read(supabaseClientProvider).auth.currentSession?.accessToken,
    fallback: YoutubeExplodeSearch(),
  ),
);

/// Từ khoá đang tìm ở màn Giải trí. Vy cũng đặt giá trị này khi người dùng nói "cho nghe nhạc xưa".
class VideoQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value.trim();
}

final videoQueryProvider = NotifierProvider<VideoQueryNotifier, String>(VideoQueryNotifier.new);

/// Kết quả tìm theo [videoQueryProvider]; rỗng khi chưa nhập gì.
final videoResultsProvider = FutureProvider.autoDispose<List<VideoItem>>((ref) async {
  final q = ref.watch(videoQueryProvider);
  if (q.isEmpty) return const [];
  return ref.read(videoSearchProvider).search(q);
});
