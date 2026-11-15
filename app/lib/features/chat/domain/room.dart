import '../../../shared/models/profile.dart';

enum RoomType { group, direct }

class Room {
  const Room({
    required this.id,
    required this.name,
    required this.type,
    required this.createdAt,
    this.peer,
    this.lastContent,
    this.lastHasImage = false,
    this.lastIsMine = false,
    this.lastAt,
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
      lastContent: m['last_content'] as String?,
      lastHasImage: m['last_has_image'] as bool? ?? false,
      lastIsMine: m['last_is_mine'] as bool? ?? false,
      lastAt: m['last_at'] == null
          ? null
          : DateTime.parse(m['last_at'] as String).toLocal(),
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

  /// Tin nhắn gần nhất (null nếu phòng chưa có tin).
  final String? lastContent;
  final bool lastHasImage;
  final bool lastIsMine;
  final DateTime? lastAt;

  bool get isDirect => type == RoomType.direct;

  /// Dòng xem trước tin nhắn gần nhất, hoặc null nếu chưa có tin.
  String? get preview {
    if (lastAt == null) return null;
    final text = (lastContent ?? '').trim();
    final body = lastHasImage
        ? (text.isEmpty ? 'Đã gửi một ảnh' : '[Ảnh] $text')
        : text;
    if (body.isEmpty) return null;
    return lastIsMine ? 'Bạn: $body' : body;
  }

  /// Tên hiển thị: chat 1-1 lấy tên người kia, phòng nhóm lấy tên phòng.
  String get displayName => isDirect ? (peer?.name ?? 'Chat riêng') : name;
}
