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

/// Tin nhắn của một phòng, cập nhật realtime.
final messagesProvider = StreamProvider.autoDispose.family<List<Message>, String>(
  (ref, roomId) => ref.watch(chatRepositoryProvider).watchMessages(roomId),
);

/// Thành viên của một phòng.
final membersProvider = FutureProvider.autoDispose.family<List<Profile>, String>(
  (ref, roomId) => ref.watch(chatRepositoryProvider).fetchMembers(roomId),
);

/// Id những người đang online trong phòng.
final onlineProvider = StreamProvider.autoDispose.family<Set<String>, String>(
  (ref, roomId) => ref.watch(chatRepositoryProvider).watchOnline(roomId),
);
