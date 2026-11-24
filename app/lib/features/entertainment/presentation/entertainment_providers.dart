import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../voice/core/vy_settings.dart';
import '../data/media_memory.dart';
import '../data/media_summary.dart';
import '../data/video_rank.dart';
import '../data/youtube_service.dart';

final videoSearchProvider = Provider<VideoSearch>(
  (ref) => CachedVideoSearch(
    RankedVideoSearch(
      ApiVideoSearch(
        accessToken: () =>
            ref.read(supabaseClientProvider).auth.currentSession?.accessToken,
        fallback: YoutubeExplodeSearch(),
      ),
      // Bài đã chê không bao giờ hiện lại; bài đã khen được ưu tiên. Đọc lúc tìm nên luôn mới nhất.
      excluded: () => ref.read(mediaMemoryProvider).dislikedIds,
      liked: () => ref.read(mediaMemoryProvider).likedIds,
    ),
  ),
);

/// Trí nhớ nghe/xem của người dùng hiện tại (lưu trên máy theo tài khoản; tắt hoặc xoá được ở Cá nhân).
class MediaMemoryNotifier extends Notifier<MediaMemory> {
  static String keyFor(String? uid) => 'media_memory_v1:${uid ?? 'anon'}';

  String? _uid;

  @override
  MediaMemory build() {
    _uid = ref.watch(currentUserProvider.select((u) => u?.id));
    _load();
    return const MediaMemory();
  }

  /// Bật "Nhớ những gì tôi đã nghe" (mặc định bật).
  bool get enabled => ref.read(vySettingsProvider).value?.rememberMedia ?? true;

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final loaded = MediaMemory.decode(p.getString(keyFor(_uid)));
      if (loaded.isEmpty) return;
      // Có thể đã ghi vài mục mới trong lúc đang đọc: giữ mục mới, thêm mục cũ chưa có.
      final have = {for (final e in state.entries) e.id};
      state = MediaMemory(entries: [...state.entries, ...loaded.entries.where((e) => !have.contains(e.id))]);
    } catch (_) {
      // Không đọc được thì coi như chưa có gì.
    }
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(keyFor(_uid), state.encode());
    } catch (_) {
      // Lưu hỏng không được làm hỏng việc đang nghe.
    }
  }

  void _apply(MediaMemory Function(MediaMemory m) f) {
    if (!enabled) return;
    state = f(state);
    _save();
  }

  void play(VideoItem v, String topic) => _apply((m) => m.recordPlay(v, topic, DateTime.now()));

  void progress(String id, {required int progressSec, int? durationSec, bool completed = false}) =>
      _apply((m) => m.updateProgress(id, progressSec: progressSec, durationSec: durationSec, completed: completed));

  void like(String id) => _apply((m) => m.setLiked(id, true));

  void dislike(String id) => _apply((m) => m.setDisliked(id, true));

  /// Xoá toàn bộ lịch sử nghe/xem (người dùng chủ động).
  Future<void> clear() async {
    state = const MediaMemory();
    await _save();
  }

  /// Tóm tắt thói quen gửi lên não Vy ({} khi tắt nhớ hoặc chưa có gì).
  Map<String, Object?> habit() {
    if (!enabled || state.isEmpty) return const {};
    return state.habitJson(DateTime.now());
  }
}

final mediaMemoryProvider = NotifierProvider<MediaMemoryNotifier, MediaMemory>(MediaMemoryNotifier.new);

/// Gửi tóm tắt nghe/xem (thể loại + số giây) lên máy chủ để người thân được cấp quyền xem. Ghi đè được trong kiểm thử.
final mediaSummaryRepositoryProvider = Provider<MediaSummaryRepository>(
  (ref) => SupabaseMediaSummaryRepository(ref.read(supabaseClientProvider)),
);

/// Tóm tắt nghe/xem 7 ngày của [ownerId] cho màn người thân. Lỗi hoặc không có quyền thì coi như rỗng.
final personMediaProvider = FutureProvider.autoDispose.family<MediaSummary, String>((ref, ownerId) async {
  try {
    final rows = await ref.read(mediaSummaryRepositoryProvider).recent(ownerId, days: 7);
    return summarizeMedia(rows, DateTime.now());
  } catch (_) {
    return summarizeMedia(const [], DateTime.now());
  }
});

/// Chỗ bắt đầu phát (giây) cho lần mở màn phát kế tiếp ("xem tiếp"). Màn phát đọc rồi xoá.
class PlayerStartAtNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void set(int? sec) => state = sec;
}

final playerStartAtProvider = NotifierProvider<PlayerStartAtNotifier, int?>(PlayerStartAtNotifier.new);

/// Người dùng đang duyệt danh sách bằng giọng ("lướt xuống", "đọc tên các video"): hiện số nhưng KHÔNG tự mở video số 1.
class VideoBrowseNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool v) {
    if (state != v) state = v;
  }
}

final videoBrowseProvider = NotifierProvider<VideoBrowseNotifier, bool>(VideoBrowseNotifier.new);

/// Chủ đề của hàng đợi đang phát ("nhạc xưa", "cải lương"): khi sắp hết bài, máy tự tìm thêm cùng chủ đề.
class VideoTopicNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String v) => state = v.trim();
}

final videoTopicProvider = NotifierProvider<VideoTopicNotifier, String>(VideoTopicNotifier.new);

/// Từ khoá đang tìm ở màn Giải trí. Vy cũng đặt giá trị này khi người dùng nói "cho nghe nhạc xưa".
class VideoQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value.trim();
}

final videoQueryProvider = NotifierProvider<VideoQueryNotifier, String>(
  VideoQueryNotifier.new,
);

/// Kết quả tìm theo [videoQueryProvider]; rỗng khi chưa nhập gì.
final videoResultsProvider = FutureProvider.autoDispose<List<VideoItem>>((
  ref,
) async {
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

final videoQueueProvider =
    NotifierProvider<VideoQueueNotifier, List<VideoItem>>(
      VideoQueueNotifier.new,
    );

/// Lệnh điều khiển trình phát (từ giọng nói của Vy hoặc nút trên màn).
enum PlayerAction {
  pause,
  play,
  next,
  previous,
  louder,
  quieter,

  /// Về giây 0 của bài đang phát.
  restart,

  /// Tua lùi/tới [PlayerCommand.value] giây.
  seekBack,
  seekForward,

  /// Rời màn phát (khác với tạm dừng).
  close,

  /// Hẹn giờ tắt sau [PlayerCommand.value] phút: nhỏ dần rồi dừng.
  sleep,

  /// "Bài này hay": nhớ để lần sau ưu tiên.
  like,

  /// "Không thích bài này": bỏ qua, sang bài khác và không mở lại.
  dislike,
}

class PlayerCommand {
  PlayerCommand(this.action, {this.value});
  final PlayerAction action;

  /// Số giây (tua) hoặc số phút (hẹn giờ); null với các lệnh khác.
  final int? value;
}

/// Mỗi lệnh là một đối tượng mới nên cùng một lệnh gửi hai lần vẫn được xử lý hai lần.
class PlayerCommandNotifier extends Notifier<PlayerCommand?> {
  @override
  PlayerCommand? build() => null;

  void send(PlayerAction a, {int? value}) => state = PlayerCommand(a, value: value);
}

/// Âm lượng của trình phát trong app (10–100, chỉnh theo âm lượng máy). Vy dựa vào đây để nói đúng sự thật:
/// đã to hết cỡ thì không báo "con tăng rồi".
class PlayerVolumeNotifier extends Notifier<int> {
  @override
  int build() => 100;

  void set(int v) => state = v.clamp(10, 100);
}

final playerVolumeProvider = NotifierProvider<PlayerVolumeNotifier, int>(PlayerVolumeNotifier.new);

/// Bài đang phát (null khi chưa mở màn phát): để Vy trả lời "bài này của ai".
class PlayerNowNotifier extends Notifier<VideoItem?> {
  @override
  VideoItem? build() => null;

  void set(VideoItem? v) => state = v;
}

final playerNowProvider = NotifierProvider<PlayerNowNotifier, VideoItem?>(PlayerNowNotifier.new);

/// Hẹn giờ tắt cần bật ngay khi màn phát mở (yêu cầu để ngủ). Màn phát đọc rồi xoá.
class PlayerStartSleepNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void set(int? minutes) => state = minutes;
}

final playerStartSleepProvider = NotifierProvider<PlayerStartSleepNotifier, int?>(PlayerStartSleepNotifier.new);

/// Hẹn giờ tắt đang chạy (số phút còn lại làm tròn lên), null nếu không hẹn.
class SleepTimerNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void set(int? minutes) => state = minutes;
}

final sleepTimerProvider = NotifierProvider<SleepTimerNotifier, int?>(SleepTimerNotifier.new);

final playerCommandProvider =
    NotifierProvider<PlayerCommandNotifier, PlayerCommand?>(
      PlayerCommandNotifier.new,
    );

/// Vy đang nhờ người dùng chọn video theo số: màn Giải trí vẽ số 1, 2, 3… ngay trên các video thật
/// (không dùng thẻ che màn). Tắt khi chọn xong, khi Vy đóng hoặc khi rời màn.
class VideoMarksNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool v) {
    if (state != v) state = v;
  }
}

final videoMarksProvider = NotifierProvider<VideoMarksNotifier, bool>(VideoMarksNotifier.new);

/// Màn phát đang mở hay không (để Vy biết có thể điều khiển).
class PlayerOpenNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool v) => state = v;
}

final playerOpenProvider = NotifierProvider<PlayerOpenNotifier, bool>(
  PlayerOpenNotifier.new,
);
