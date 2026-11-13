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

/// Danh sách đang phát: hết bài thì máy tự sang bài kế tiếp trong danh sách này.
class VideoQueueNotifier extends Notifier<List<VideoItem>> {
  @override
  List<VideoItem> build() => const [];

  void set(List<VideoItem> items) => state = items;
}

final videoQueueProvider = NotifierProvider<VideoQueueNotifier, List<VideoItem>>(VideoQueueNotifier.new);

/// Lệnh điều khiển trình phát (từ giọng nói của Vy hoặc nút trên màn).
enum PlayerAction { pause, play, next, previous, louder, quieter }

class PlayerCommand {
  PlayerCommand(this.action);
  final PlayerAction action;
}

/// Mỗi lệnh là một đối tượng mới nên cùng một lệnh gửi hai lần vẫn được xử lý hai lần.
class PlayerCommandNotifier extends Notifier<PlayerCommand?> {
  @override
  PlayerCommand? build() => null;

  void send(PlayerAction a) => state = PlayerCommand(a);
}

final playerCommandProvider = NotifierProvider<PlayerCommandNotifier, PlayerCommand?>(PlayerCommandNotifier.new);

/// Màn phát đang mở hay không (để Vy biết có thể điều khiển).
class PlayerOpenNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool v) => state = v;
}

final playerOpenProvider = NotifierProvider<PlayerOpenNotifier, bool>(PlayerOpenNotifier.new);
