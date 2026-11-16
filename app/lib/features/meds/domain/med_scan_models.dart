import 'meds_models.dart';

/// Mức tin cậy của một mục đọc từ ảnh, do máy chủ kiểm đoạn trích có thật trong chữ đọc được.
enum ScanStatus {
  ok,
  fuzzy,
  none;

  static ScanStatus of(Object? v) => switch (v) {
    'ok' => ScanStatus.ok,
    'fuzzy' => ScanStatus.fuzzy,
    _ => ScanStatus.none,
  };

  /// Mục dùng được để điền vào bản nháp (không có bằng chứng thì bỏ trống).
  bool get usable => this != ScanStatus.none;
}

/// Giờ gợi ý theo tên cữ. Đơn thuốc hiếm khi ghi giờ, nên đây luôn là giờ do app đặt, người dùng chỉnh lại.
String defaultTimeFor(String label) => switch (label.trim().toLowerCase()) {
  'sáng' => '07:00',
  'trưa' => '11:30',
  'chiều' => '17:00',
  'tối' => '20:30',
  _ => '21:30',
};

class ScanItem {
  const ScanItem({
    required this.name,
    this.strength,
    this.qty = 1,
    this.unit = 'viên',
    this.evidence = '',
    required this.status,
  });

  factory ScanItem.fromJson(Map<String, dynamic> m) => ScanItem(
    name: m['name'] as String,
    strength: m['strength'] as String?,
    qty: (m['qty'] as num?)?.toDouble() ?? 1,
    unit: (m['unit'] as String?) ?? 'viên',
    evidence: (m['evidence'] as String?) ?? '',
    status: ScanStatus.of(m['status']),
  );

  final String name;
  final String? strength;
  final double qty;
  final String unit;
  final String evidence;
  final ScanStatus status;

  MedItem toItem() =>
      MedItem(name: name, strength: strength, qty: qty, unit: unit);
}

class ScanSlot {
  const ScanSlot({
    required this.label,
    this.meal,
    this.evidence = '',
    required this.status,
    this.items = const [],
  });

  factory ScanSlot.fromJson(Map<String, dynamic> m) => ScanSlot(
    label: m['label'] as String,
    meal: MealRel.of(m['meal'] as String?),
    evidence: (m['evidence'] as String?) ?? '',
    status: ScanStatus.of(m['status']),
    items: [
      for (final i in (m['items'] as List? ?? const []))
        ScanItem.fromJson(Map<String, dynamic>.from(i as Map)),
    ],
  );

  final String label;
  final MealRel? meal;
  final String evidence;
  final ScanStatus status;
  final List<ScanItem> items;

  List<ScanItem> get usableItems => [
    for (final i in items)
      if (i.status.usable) i,
  ];

  /// Cữ được đưa vào bản nháp khi chính cữ đó có bằng chứng, hoặc có ít nhất một thuốc có bằng chứng.
  bool get usable => status.usable || usableItems.isNotEmpty;
}

class ScanPrn {
  const ScanPrn({
    required this.name,
    this.instruction,
    this.evidence = '',
    required this.status,
  });

  factory ScanPrn.fromJson(Map<String, dynamic> m) => ScanPrn(
    name: m['name'] as String,
    instruction: m['instruction'] as String?,
    evidence: (m['evidence'] as String?) ?? '',
    status: ScanStatus.of(m['status']),
  );

  final String name;
  final String? instruction;
  final String evidence;
  final ScanStatus status;
}

class ScanResult {
  const ScanResult({
    this.title = '',
    this.days,
    this.recheck,
    this.slots = const [],
    this.prn = const [],
  });

  factory ScanResult.fromJson(Map<String, dynamic> m) => ScanResult(
    title: (m['title'] as String?) ?? '',
    days: (m['days'] as num?)?.toInt(),
    recheck: m['recheck'] == null
        ? null
        : DateTime.tryParse(m['recheck'] as String),
    slots: [
      for (final s in (m['slots'] as List? ?? const []))
        ScanSlot.fromJson(Map<String, dynamic>.from(s as Map)),
    ],
    prn: [
      for (final p in (m['prn'] as List? ?? const []))
        ScanPrn.fromJson(Map<String, dynamic>.from(p as Map)),
    ],
  );

  final String title;
  final int? days;
  final DateTime? recheck;
  final List<ScanSlot> slots;
  final List<ScanPrn> prn;

  bool get isEmpty =>
      !slots.any((s) => s.usable) && !prn.any((p) => p.status.usable);

  /// Số mục đã bị bỏ vì không thấy trong ảnh.
  int get dropped =>
      slots.fold(0, (n, s) => n + s.items.where((i) => !i.status.usable).length) +
      prn.where((p) => !p.status.usable).length +
      slots.where((s) => !s.usable).length;

  /// Bản nháp để người dùng kiểm tra trên màn sửa đơn. Chưa lưu, chưa có báo thức:
  /// chỉ khi người dùng bấm "Lưu lịch thuốc" thì đơn mới có hiệu lực.
  MedPlan toDraft(DateTime now) {
    final start = DateTime(now.year, now.month, now.day);
    final slots = [
      for (final s in this.slots)
        if (s.usable)
          MedSlot(
            label: s.label,
            time: defaultTimeFor(s.label),
            mealRel: s.meal,
            items: [for (final i in s.usableItems) i.toItem()],
          ),
    ]..sort((a, b) => a.time.compareTo(b.time));
    return MedPlan(
      title: title.isEmpty
          ? 'Đơn thuốc ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}'
          : title,
      startDate: start,
      endDate: days == null ? null : start.add(Duration(days: days! - 1)),
      recheckDate: recheck != null && recheck!.isAfter(start) ? recheck : null,
      slots: slots,
      prn: [
        for (final p in prn)
          if (p.status.usable)
            MedPrn(name: p.name, instruction: p.instruction),
      ],
    );
  }
}
