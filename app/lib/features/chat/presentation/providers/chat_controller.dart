import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/room.dart';
import 'chat_providers.dart';

/// Các hành động của chat; state là trạng thái loading/lỗi của hành động gần nhất.
class ChatController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Trả về phòng mới, hoặc `null` nếu lỗi (lỗi nằm trong state).
  Future<Room?> createRoom(String name) async {
    state = const AsyncLoading();
    Room? room;
    state = await AsyncValue.guard(() async {
      room = await ref.read(chatRepositoryProvider).createRoom(name);
    });
    if (room != null) ref.invalidate(roomsProvider);
    return room;
  }

  /// Mở chat riêng với một username; trả về `null` nếu lỗi (lỗi nằm trong state).
  Future<Room?> openDirectRoom(String username) async {
    state = const AsyncLoading();
    Room? room;
    state = await AsyncValue.guard(() async {
      room = await ref.read(chatRepositoryProvider).openDirectRoom(username);
    });
    if (room != null) ref.invalidate(roomsProvider);
    return room;
  }

  Future<bool> addMember(String roomId, String username) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(chatRepositoryProvider).addMember(roomId, username),
    );
    if (!state.hasError) ref.invalidate(membersProvider(roomId));
    return !state.hasError;
  }

  /// Gửi tin nhắn. Lỗi nằm trong state; tin mới tới qua stream realtime.
  Future<bool> send(String roomId, String content) async {
    state = await AsyncValue.guard(
      () => ref.read(chatRepositoryProvider).sendMessage(roomId, content),
    );
    return !state.hasError;
  }

  /// Gửi ảnh kèm chú thích tùy chọn. Lỗi nằm trong state; tin mới tới qua stream realtime.
  Future<bool> sendImage(String roomId, Uint8List bytes, String caption) async {
    state = await AsyncValue.guard(
      () => ref.read(chatRepositoryProvider).sendImage(roomId, bytes, caption: caption),
    );
    return !state.hasError;
  }
}

final chatControllerProvider = AsyncNotifierProvider<ChatController, void>(ChatController.new);
