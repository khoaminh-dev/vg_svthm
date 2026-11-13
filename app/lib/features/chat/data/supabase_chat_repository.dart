import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../../../shared/models/profile.dart';
import '../domain/chat_repository.dart';
import '../domain/message.dart';
import '../domain/room.dart';
import 'chat_error_mapper.dart';

class SupabaseChatRepository implements ChatRepository {
  SupabaseChatRepository(this._client);

  final SupabaseClient _client;

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AppFailure('Phiên đăng nhập đã hết hạn');
    return id;
  }

  @override
  Future<List<Room>> fetchRooms() => _guard(() async {
    final rows = await _client.rpc('my_rooms') as List<dynamic>;
    return rows.map((r) => Room.fromMap(r as Map<String, dynamic>)).toList();
  });

  @override
  Future<Room> createRoom(String name) => _guard(() async {
    // Một RPC duy nhất: tạo phòng và thêm người tạo trong cùng một giao dịch (không để phòng mồ côi).
    final rows = await _client.rpc('create_group_room', params: {'p_name': name}) as List<dynamic>;
    final row = rows.first as Map<String, dynamic>;
    return Room(
      id: row['id'] as String,
      name: row['name'] as String,
      type: RoomType.group,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  });

  @override
  Future<Room> openDirectRoom(String username) async {
    try {
      final id = await _client.rpc(
        'create_or_get_direct_room',
        params: {'p_username': username},
      ) as String;
      final rooms = await fetchRooms();
      return rooms.firstWhere((r) => r.id == id);
    } catch (e) {
      throw mapChatError(e);
    }
  }

  @override
  Stream<void> watchJoinedRooms() {
    late final StreamController<void> controller;
    RealtimeChannel? channel;

    controller = StreamController<void>(
      onListen: () {
        channel = _client
            .channel('joined-rooms:$_uid')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'room_members',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: _uid,
              ),
              callback: (_) => controller.add(null),
            )
            .subscribe();
      },
      onCancel: () async {
        final ch = channel;
        if (ch != null) await _client.removeChannel(ch);
      },
    );
    return controller.stream;
  }

  @override
  Future<void> addMember(String roomId, String username) => _guard(
    () => _client.rpc('add_member_by_username', params: {'p_room': roomId, 'p_username': username}),
  );

  @override
  Future<List<Profile>> fetchMembers(String roomId) => _guard(() async {
    final members = await _client.from('room_members').select('user_id').eq('room_id', roomId);
    final ids = members.map((m) => m['user_id'] as String).toList();
    if (ids.isEmpty) return <Profile>[];
    final rows = await _client.from('profiles').select().inFilter('id', ids);
    return rows.map(Profile.fromMap).toList();
  });

  /// Số tin nhắn mới nhất được nạp cho mỗi phòng (không tải toàn bộ lịch sử).
  static const messageWindow = 50;

  @override
  Stream<List<Message>> watchMessages(String roomId) => _client
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('room_id', roomId)
      .order('created_at', ascending: false)
      .limit(messageWindow)
      .map((rows) => rows.map(Message.fromMap).toList().reversed.toList());

  @override
  Future<List<Message>> fetchOlderMessages(
    String roomId, {
    required DateTime before,
    int limit = 50,
  }) => _guard(() async {
    final rows = await _client
        .from('messages')
        .select()
        .eq('room_id', roomId)
        .lt('created_at', before.toUtc().toIso8601String())
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(Message.fromMap).toList().reversed.toList();
  });

  @override
  Stream<void> watchMembers(String roomId) {
    late final StreamController<void> controller;
    RealtimeChannel? channel;

    controller = StreamController<void>(
      onListen: () {
        channel = _client
            .channel('members:$roomId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'room_members',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'room_id',
                value: roomId,
              ),
              callback: (_) => controller.add(null),
            )
            .subscribe();
      },
      onCancel: () async {
        final ch = channel;
        if (ch != null) await _client.removeChannel(ch);
      },
    );
    return controller.stream;
  }

  @override
  Future<void> sendMessage(String roomId, String content) => _guard(
    () => _client.from('messages').insert({
      'room_id': roomId,
      'user_id': _uid,
      'content': content.trim(),
    }),
  );

  static const _imageBucket = 'chat-images';
  static const maxImageBytes = 5 * 1024 * 1024;

  /// Nhận dạng định dạng theo nội dung file (không tin đuôi file). Null nếu không hỗ trợ.
  static ({String ext, String mime})? imageKind(Uint8List b) {
    bool at(int i, List<int> sig) {
      if (b.length < i + sig.length) return false;
      for (var k = 0; k < sig.length; k++) {
        if (b[i + k] != sig[k]) return false;
      }
      return true;
    }

    if (at(0, [0xFF, 0xD8, 0xFF])) return (ext: 'jpg', mime: 'image/jpeg');
    if (at(0, [0x89, 0x50, 0x4E, 0x47])) return (ext: 'png', mime: 'image/png');
    if (at(0, [0x52, 0x49, 0x46, 0x46]) && at(8, [0x57, 0x45, 0x42, 0x50])) {
      return (ext: 'webp', mime: 'image/webp');
    }
    return null;
  }

  @override
  Future<void> sendImage(String roomId, Uint8List bytes, {String caption = ''}) => _guard(() async {
    final uid = _uid;
    if (bytes.length > maxImageBytes) throw const AppFailure('Ảnh quá lớn (tối đa 5 MB)');
    final kind = imageKind(bytes);
    if (kind == null) throw const AppFailure('Chỉ gửi được ảnh JPG, PNG hoặc WebP');
    final name = '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}.${kind.ext}';
    final path = '$roomId/$uid/$name';

    await _client.storage
        .from(_imageBucket)
        .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: kind.mime));
    try {
      await _client.from('messages').insert({
        'room_id': roomId,
        'user_id': uid,
        'content': caption.trim(),
        'image_path': path,
      });
    } catch (e) {
      // Không để lại ảnh mồ côi nếu tạo tin nhắn thất bại.
      try {
        await _client.storage.from(_imageBucket).remove([path]);
      } catch (_) {}
      rethrow;
    }
  });

  @override
  Future<String?> imageUrl(String imagePath) async {
    try {
      return await _client.storage.from(_imageBucket).createSignedUrl(imagePath, 3600);
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<Set<String>> watchOnline(String roomId) {
    late final StreamController<Set<String>> controller;
    RealtimeChannel? channel;

    controller = StreamController<Set<String>>(
      onListen: () {
        final ch = _client.channel('presence:room:$roomId', opts: RealtimeChannelConfig(key: _uid));
        channel = ch;
        ch
            .onPresenceSync((_) {
              controller.add(ch.presenceState().map((s) => s.key).toSet());
            })
            .subscribe((status, _) async {
              if (status == RealtimeSubscribeStatus.subscribed) {
                await ch.track({'online_at': DateTime.now().toIso8601String()});
              }
            });
      },
      onCancel: () async {
        final ch = channel;
        if (ch != null) {
          await ch.untrack();
          await _client.removeChannel(ch);
        }
      },
    );
    return controller.stream;
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } catch (e) {
      throw mapChatError(e);
    }
  }
}
