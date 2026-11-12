class Room {
  const Room({required this.id, required this.name, required this.createdAt});

  factory Room.fromMap(Map<String, dynamic> m) => Room(
        id: m['id'] as String,
        name: m['name'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  final String id;
  final String name;
  final DateTime createdAt;
}
