/// Quan hệ của người chăm sóc với người được chăm sóc (cột `relation`).
enum Relation {
  con('con', 'Con'),
  chau('chau', 'Cháu'),
  voChong('vo_chong', 'Vợ/chồng'),
  khac('khac', 'Người thân');

  const Relation(this.code, this.label);

  final String code;
  final String label;

  static Relation of(String? code) => Relation.values.firstWhere(
    (r) => r.code == code,
    orElse: () => Relation.khac,
  );
}

/// Các quyền cha mẹ cấp cho người chăm sóc (khoá trong `family_links.perms`).
abstract final class FamilyPerm {
  static const health = 'health';
  static const recordBp = 'record_bp';
  static const medsView = 'meds_view';
  static const medsEdit = 'meds_edit';
  static const location = 'location';
  static const profileEdit = 'profile_edit';
  static const vyHistory = 'vy_history';
  static const alerts = 'alerts';

  /// Thứ tự và nhãn hiển thị trong màn quản lý quyền.
  static const labels = <String, String>{
    health: 'Xem huyết áp và nguy cơ sức khoẻ',
    alerts: 'Nhận cảnh báo khi có chuyện',
    recordBp: 'Đo huyết áp hộ',
    medsView: 'Xem lịch uống thuốc',
    medsEdit: 'Đặt và sửa lịch uống thuốc',
    location: 'Xem vị trí',
    profileEdit: 'Sửa hồ sơ sức khoẻ',
    vyHistory: 'Xem lịch sử hỏi Vy và thể loại nhạc, video đã nghe',
  };
}

/// Một liên kết gia đình nhìn từ phía người dùng hiện tại (kết quả hàm `my_family`).
class FamilyLink {
  const FamilyLink({
    required this.linkId,
    required this.role,
    required this.otherId,
    required this.relation,
    required this.perms,
    required this.status,
    required this.createdAt,
    this.otherName,
    this.otherUsername,
    this.otherAvatar,
  });

  factory FamilyLink.fromMap(Map<String, dynamic> m) => FamilyLink(
    linkId: m['link_id'] as String,
    role: m['role'] as String,
    otherId: m['other_id'] as String,
    otherName: m['other_name'] as String?,
    otherUsername: m['other_username'] as String?,
    otherAvatar: m['other_avatar'] as String?,
    relation: Relation.of(m['relation'] as String?),
    perms: {
      for (final e in ((m['perms'] as Map?) ?? const {}).entries)
        if (e.value is bool) e.key as String: e.value as bool,
    },
    status: m['status'] as String,
    createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
  );

  final String linkId;

  /// `owner` = tôi là người được chăm sóc (người kia đang theo dõi tôi); `carer` = tôi đang theo dõi người kia.
  final String role;
  final String otherId;
  final String? otherName;
  final String? otherUsername;
  final String? otherAvatar;
  final Relation relation;
  final Map<String, bool> perms;
  final String status;
  final DateTime createdAt;

  bool get iAmOwner => role == 'owner';
  bool get active => status == 'active';
  bool can(String perm) => perms[perm] == true;

  String get name {
    final n = otherName?.trim();
    if (n != null && n.isNotEmpty) return n;
    return otherUsername ?? 'Người thân';
  }
}

/// Kết quả nhập mã mời: thành công có [linkId], thất bại có [error] (`invalid_code`, `too_many_attempts`, `self_link`).
class RedeemResult {
  const RedeemResult({this.linkId, this.error});

  final String? linkId;
  final String? error;

  bool get ok => linkId != null && error == null;

  String get message => switch (error) {
    'invalid_code' =>
      'Mã không đúng hoặc đã hết hạn. Nhờ người thân tạo mã mới nhé.',
    'too_many_attempts' =>
      'Bạn nhập sai quá nhiều lần. Chờ ít phút rồi thử lại.',
    'self_link' =>
      'Đây là mã của chính bạn. Hãy nhập mã trên máy của người thân.',
    _ => 'Chưa liên kết được, bạn thử lại nhé.',
  };
}

/// Một dòng trong nhật ký gia đình.
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.action,
    required this.at,
    this.actorName,
    this.detail = const {},
  });

  final int id;
  final String action;
  final DateTime at;
  final String? actorName;
  final Map<String, dynamic> detail;

  String get text {
    final who = actorName ?? 'Ai đó';
    return switch (action) {
      'link_created' => '$who đã được thêm vào danh sách theo dõi',
      'link_revoked_by_owner' => 'Bạn đã gỡ một người theo dõi',
      'link_left_by_carer' => '$who đã ngừng theo dõi',
      'perms_changed' => 'Bạn đã đổi quyền của một người theo dõi',
      'nudge_measure' => '$who đã nhờ bạn đo huyết áp',
      'view_location' => '$who đã xem vị trí của bạn',
      'edit_meds' => '$who đã sửa lịch uống thuốc',
      'edit_profile' => '$who đã sửa hồ sơ sức khoẻ',
      'edit_emergency_card' => '$who đã sửa thẻ y tế khẩn cấp',
      _ => '$who: $action',
    };
  }
}
