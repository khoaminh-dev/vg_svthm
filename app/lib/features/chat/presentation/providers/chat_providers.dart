import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../../../shared/models/profile.dart';
import '../../data/supabase_chat_repository.dart';
import '../../domain/chat_repository.dart';
import '../../domain/message.dart';
import '../../domain/room.dart';

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
