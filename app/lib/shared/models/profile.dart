/// Hồ sơ công khai của một người dùng (bảng `profiles`).
class Profile {
  const Profile({required this.id, this.username, this.displayName, this.avatarUrl});

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
    id: m['id'] as String,
    username: m['username'] as String?,
    displayName: m['display_name'] as String?,
    avatarUrl: m['avatar_url'] as String?,
  );

  final String id;
  final String? username;
  final String? displayName;
  final String? avatarUrl;

  String get name =>
      (displayName?.trim().isNotEmpty ?? false) ? displayName! : (username ?? 'Người dùng');
}
