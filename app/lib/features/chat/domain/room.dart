import '../../../shared/models/profile.dart';

enum RoomType { group, direct }

class Room {
  const Room({
    required this.id,
    required this.name,
    required this.type,
    required this.createdAt,
    this.peer,
  });

  /// Tạo từ một dòng của hàm `my_rooms()`.
  factory Room.fromMap(Map<String, dynamic> m) {
    final type = m['type'] == 'direct' ? RoomType.direct : RoomType.group;
    final peerId = m['peer_id'] as String?;
    return Room(
      id: m['id'] as String,
      name: m['name'] as String,
      type: type,
      createdAt: DateTime.parse(m['created_at'] as String),
      peer: peerId == null
          ? null
          : Profile(
              id: peerId,
              username: m['peer_username'] as String?,
              displayName: m['peer_name'] as String?,
              avatarUrl: m['peer_avatar_url'] as String?,
            ),
    );
  }

  final String id;
  final String name;
  final RoomType type;
  final DateTime createdAt;

  /// Người còn lại trong chat 1-1 (null với phòng nhóm).
  final Profile? peer;

  bool get isDirect => type == RoomType.direct;

  /// Tên hiển thị: chat 1-1 lấy tên người kia, phòng nhóm lấy tên phòng.
  String get displayName => isDirect ? (peer?.name ?? 'Chat riêng') : name;
}
