class Message {
  const Message({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.content,
    required this.createdAt,
    this.imagePath,
    this.imageExpired = false,
  });

  factory Message.fromMap(Map<String, dynamic> m) => Message(
    id: m['id'] as int,
    roomId: m['room_id'] as String,
    userId: m['user_id'] as String,
    content: (m['content'] as String?) ?? '',
    createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
    imagePath: m['image_path'] as String?,
    imageExpired: m['image_expired_at'] != null,
  );

  final int id;
  final String roomId;
  final String userId;

  /// Nội dung chữ; với tin có ảnh đây là chú thích (có thể rỗng).
  final String content;
  final DateTime createdAt;

  /// Đường dẫn ảnh trong kho `chat-images` (null nếu tin không có ảnh hoặc ảnh đã hết hạn).
  final String? imagePath;

  /// Ảnh đã bị dọn sau thời hạn lưu trữ.
  final bool imageExpired;

  bool get hasImage => imagePath != null;
}
