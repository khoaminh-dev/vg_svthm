import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../../shared/models/profile.dart';
import '../../data/supabase_chat_repository.dart';
import '../../domain/chat_repository.dart';
import '../../domain/message.dart';
import '../../domain/room.dart';
import '../../data/supabase_chat_repository.dart' show SupabaseChatRepository;

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => SupabaseChatRepository(ref.watch(supabaseClientProvider)),
);

/// Các phòng của người dùng hiện tại.
final roomsProvider = FutureProvider.autoDispose<List<Room>>(
  (ref) => ref.watch(chatRepositoryProvider).fetchRooms(),
);

/// Mỗi khi mình được thêm vào phòng mới thì làm mới danh sách phòng.
final joinedRoomsProvider = StreamProvider.autoDispose<void>((ref) {
  return ref.watch(chatRepositoryProvider).watchJoinedRooms().map((_) {
    ref.invalidate(roomsProvider);
  });
});

/// Tin nhắn của một phòng, cập nhật realtime.
final messagesProvider = StreamProvider.autoDispose.family<List<Message>, String>(
  (ref, roomId) => ref.watch(chatRepositoryProvider).watchMessages(roomId),
);

/// Đường dẫn tạm để xem ảnh trong chat (giữ trong bộ nhớ để cuộn danh sách không tải lại).
final chatImageUrlProvider = FutureProvider.family<String?, String>(
  (ref, path) => ref.watch(chatRepositoryProvider).imageUrl(path),
);

/// Thành viên của một phòng.
final membersProvider = FutureProvider.autoDispose.family<List<Profile>, String>((ref, roomId) {
  final repo = ref.watch(chatRepositoryProvider);
  // Có người được thêm/xoá thì tải lại danh sách (để tên hiển thị đúng ngay).
  final sub = repo.watchMembers(roomId).listen((_) => ref.invalidateSelf(), onError: (_) {});
  ref.onDispose(sub.cancel);
  return repo.fetchMembers(roomId);
});

/// Id những người đang online trong phòng.
final onlineProvider = StreamProvider.autoDispose.family<Set<String>, String>(
  (ref, roomId) => ref.watch(chatRepositoryProvider).watchOnline(roomId),
);

/// Tin nhắn cũ đã tải thêm (phân trang kiểu keyset theo thời gian), ngoài cửa sổ realtime mới nhất.
class OlderMessagesState {
  const OlderMessagesState({this.items = const [], this.hasMore = true, this.loading = false});

  final List<Message> items;
  final bool hasMore;
  final bool loading;
}

class OlderMessagesNotifier extends Notifier<OlderMessagesState> {
  OlderMessagesNotifier(this.roomId);

  final String roomId;

  @override
  OlderMessagesState build() => const OlderMessagesState();

  /// Tải thêm một trang tin cũ hơn [oldestShown] (tin cũ nhất đang hiển thị).
  Future<void> loadMore(DateTime oldestShown) async {
    if (state.loading || !state.hasMore) return;
    state = OlderMessagesState(items: state.items, hasMore: state.hasMore, loading: true);
    try {
      const page = 50;
      final older = await ref
          .read(chatRepositoryProvider)
          .fetchOlderMessages(roomId, before: oldestShown, limit: page);
      state = OlderMessagesState(items: [...older, ...state.items], hasMore: older.length >= page);
    } catch (_) {
      state = OlderMessagesState(items: state.items, hasMore: state.hasMore);
    }
  }
}

final olderMessagesProvider = NotifierProvider.autoDispose
    .family<OlderMessagesNotifier, OlderMessagesState, String>(
      (roomId) => OlderMessagesNotifier(roomId),
    );

/// Kích thước cửa sổ realtime: chỉ khi đủ chừng này tin thì mới có thể còn tin cũ hơn.
const messageWindowSize = SupabaseChatRepository.messageWindow;
