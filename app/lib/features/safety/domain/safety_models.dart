/// Một lần bấm SOS.
class SosEvent {
  const SosEvent({
    required this.id,
    required this.ownerId,
    required this.createdAt,
    required this.handled,
    this.cancelled = false,
    this.handledBy,
    this.handledAt,
    this.lat,
    this.lng,
  });

  factory SosEvent.fromMap(Map<String, dynamic> m) => SosEvent(
    id: m['id'] as String,
    ownerId: m['owner_id'] as String,
    createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
    handled: m['status'] == 'handled',
    cancelled: m['cancelled'] == true,
    handledBy: m['handled_by'] as String?,
    handledAt: m['handled_at'] == null
        ? null
        : DateTime.parse(m['handled_at'] as String).toLocal(),
    lat: (m['lat'] as num?)?.toDouble(),
    lng: (m['lng'] as num?)?.toDouble(),
  );

  final String id;
  final String ownerId;
  final DateTime createdAt;
  final bool handled;
  final bool cancelled;
  final String? handledBy;
  final DateTime? handledAt;

  /// Vị trí lúc bấm SOS (có sau vài giây nếu người dùng cho phép).
  final double? lat;
  final double? lng;
  bool get hasLocation => lat != null && lng != null;

  /// SOS còn mở: chưa ai nhận, chưa huỷ.
  bool get open => !handled;
}

class CardContact {
  const CardContact({required this.name, required this.phone});

  factory CardContact.fromMap(Map<String, dynamic> m) => CardContact(
    name: (m['name'] as String?) ?? '',
    phone: (m['phone'] as String?) ?? '',
  );

  final String name;
  final String phone;

  Map<String, dynamic> toMap() => {'name': name, 'phone': phone};
}

/// Thẻ y tế khẩn cấp: những điều người cứu hộ cần biết ngay.
class EmergencyCard {
  const EmergencyCard({
    this.bloodType,
    this.allergies,
    this.conditions,
    this.ownPhone,
    this.contacts = const [],
    this.note,
  });

  factory EmergencyCard.fromMap(Map<String, dynamic> m) => EmergencyCard(
    bloodType: m['blood_type'] as String?,
    allergies: m['allergies'] as String?,
    conditions: m['conditions'] as String?,
    ownPhone: m['own_phone'] as String?,
    note: m['note'] as String?,
    contacts: [
      for (final c in (m['contacts'] as List? ?? const []))
        CardContact.fromMap(Map<String, dynamic>.from(c as Map)),
    ],
  );

  final String? bloodType;
  final String? allergies;
  final String? conditions;
  final String? ownPhone;
  final List<CardContact> contacts;
  final String? note;

  bool get isEmpty =>
      (bloodType ?? '').isEmpty &&
      (allergies ?? '').isEmpty &&
      (conditions ?? '').isEmpty &&
      (ownPhone ?? '').isEmpty &&
      contacts.isEmpty &&
      (note ?? '').isEmpty;

  Map<String, dynamic> toMap() => {
    'blood_type': bloodType,
    'allergies': allergies,
    'conditions': conditions,
    'own_phone': ownPhone,
    'note': note,
    'contacts': [for (final c in contacts) c.toMap()],
  };
}

const bloodTypes = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

/// Số điện thoại để bấm gọi: bỏ khoảng trắng, chấm, gạch.
String dialable(String phone) => phone.replaceAll(RegExp(r'[\s.\-]'), '');
