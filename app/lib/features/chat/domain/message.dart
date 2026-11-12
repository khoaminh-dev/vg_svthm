class Message {
  const Message({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.content,
    required this.createdAt,
  });

  factory Message.fromMap(Map<String, dynamic> m) => Message(
    id: m['id'] as int,
    roomId: m['room_id'] as String,
    userId: m['user_id'] as String,
    content: m['content'] as String,
    createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
  );

  final int id;
  final String roomId;
  final String userId;
  final String content;
  final DateTime createdAt;
}
