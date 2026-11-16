/// Chỉ dẫn ăn uống đi kèm một cữ thuốc.
enum MealRel {
  beforeMeal('before_meal', 'Trước ăn'),
  afterMeal('after_meal', 'Sau ăn'),
  withMeal('with_meal', 'Trong bữa ăn'),
  empty('empty', 'Lúc đói'),
  bedtime('bedtime', 'Trước khi ngủ');

  const MealRel(this.code, this.label);

  final String code;
  final String label;

  static MealRel? of(String? code) {
    for (final m in values) {
      if (m.code == code) return m;
    }
    return null;
  }
}

const medUnits = ['viên', 'gói', 'ml', 'đơn vị', 'giọt'];

/// Một loại thuốc trong cữ. `jar` = lấy thêm từ hũ, ngoài túi chia sẵn.
class MedItem {
  const MedItem({
    required this.name,
    this.strength,
    this.qty = 1,
    this.unit = 'viên',
    this.fromJar = false,
  });

  factory MedItem.fromJson(Map<String, dynamic> m) => MedItem(
    name: m['name'] as String,
    strength: (m['strength'] as String?)?.trim().isEmpty ?? true
        ? null
        : m['strength'] as String,
    qty: (m['qty'] as num?)?.toDouble() ?? 1,
    unit: (m['unit'] as String?) ?? 'viên',
    fromJar: m['source'] == 'jar',
  );

  final String name;
  final String? strength;
  final double qty;
  final String unit;
  final bool fromJar;

  Map<String, dynamic> toJson() => {
    'name': name,
    'strength': strength,
    'qty': qty,
    'unit': unit,
    'source': fromJar ? 'jar' : 'bag',
  };

  static String _num(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  /// "Amlodipin 5mg x1 viên"
  String get text =>
      '$name${strength == null ? '' : ' $strength'} x${_num(qty)} $unit';
}

/// Một cữ uống: túi chia sẵn (hoặc danh sách thuốc) vào một giờ cố định.
class MedSlot {
  const MedSlot({
    this.id,
    required this.label,
    required this.time,
    this.bag = true,
    this.mealRel,
    this.daysOfWeek = const [1, 2, 3, 4, 5, 6, 7],
    this.windowAfterMin = 120,
    this.bagsRemaining,
    this.items = const [],
  });

  factory MedSlot.fromJson(Map<String, dynamic> m) {
    final t = (m['time_local'] as String).split(':');
    return MedSlot(
      id: m['id'] as String?,
      label: m['label'] as String,
      time: '${t[0]}:${t[1]}',
      bag: m['mode'] != 'list',
      mealRel: MealRel.of(m['meal_rel'] as String?),
      daysOfWeek: [
        for (final d
            in (m['days_of_week'] as List? ?? const [1, 2, 3, 4, 5, 6, 7]))
          (d as num).toInt(),
      ],
      windowAfterMin: (m['window_after_min'] as num?)?.toInt() ?? 120,
      bagsRemaining: (m['bags_remaining'] as num?)?.toInt(),
      items: [
        for (final i in (m['med_items'] as List? ?? const []))
          MedItem.fromJson(Map<String, dynamic>.from(i as Map)),
      ],
    );
  }

  final String? id;
  final String label;

  /// "HH:MM" theo giờ của người được chăm sóc.
  final String time;
  final bool bag;
  final MealRel? mealRel;
  final List<int> daysOfWeek;
  final int windowAfterMin;
  final int? bagsRemaining;
  final List<MedItem> items;

  Map<String, dynamic> toJson() => {
    'label': label,
    'time': time,
    'mode': bag ? 'bag' : 'list',
    'meal_rel': mealRel?.code,
    'days_of_week': daysOfWeek,
    'window_after_min': windowAfterMin,
    'bags_remaining': bagsRemaining,
    'items': [for (final i in items) i.toJson()],
  };

  MedSlot copyWith({
    String? label,
    String? time,
    bool? bag,
    MealRel? Function()? mealRel,
    int? Function()? bagsRemaining,
    List<MedItem>? items,
  }) => MedSlot(
    id: id,
    label: label ?? this.label,
    time: time ?? this.time,
    bag: bag ?? this.bag,
    mealRel: mealRel != null ? mealRel() : this.mealRel,
    daysOfWeek: daysOfWeek,
    windowAfterMin: windowAfterMin,
    bagsRemaining: bagsRemaining != null ? bagsRemaining() : this.bagsRemaining,
    items: items ?? this.items,
  );
}

/// Thuốc "khi cần" (không đặt giờ): ngậm khi đau ngực, hạ sốt...
class MedPrn {
  const MedPrn({required this.name, this.instruction, this.maxPerDay});

  factory MedPrn.fromJson(Map<String, dynamic> m) => MedPrn(
    name: m['name'] as String,
    instruction: m['instruction'] as String?,
    maxPerDay: (m['max_per_day'] as num?)?.toInt(),
  );

  final String name;
  final String? instruction;
  final int? maxPerDay;

  Map<String, dynamic> toJson() => {
    'name': name,
    'instruction': instruction,
    'max_per_day': maxPerDay,
  };
}

DateTime _date(String s) => DateTime.parse(s);

/// Một đơn thuốc: gom các cữ, có ngày bắt đầu, kết thúc và tái khám.
class MedPlan {
  const MedPlan({
    this.id,
    required this.title,
    required this.startDate,
    this.endDate,
    this.recheckDate,
    this.doctor,
    this.note,
    this.active = true,
    this.slots = const [],
    this.prn = const [],
  });

  factory MedPlan.fromJson(Map<String, dynamic> m) {
    final slots = [
      for (final s in (m['med_slots'] as List? ?? const []))
        MedSlot.fromJson(Map<String, dynamic>.from(s as Map)),
    ]..sort((a, b) => a.time.compareTo(b.time));
    return MedPlan(
      id: m['id'] as String?,
      title: m['title'] as String,
      startDate: _date(m['start_date'] as String),
      endDate: m['end_date'] == null ? null : _date(m['end_date'] as String),
      recheckDate: m['recheck_date'] == null
          ? null
          : _date(m['recheck_date'] as String),
      doctor: m['doctor'] as String?,
      note: m['note'] as String?,
      active: m['status'] != 'ended',
      slots: slots,
      prn: [
        for (final p in (m['med_prn'] as List? ?? const []))
          MedPrn.fromJson(Map<String, dynamic>.from(p as Map)),
      ],
    );
  }

  final String? id;
  final String title;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime? recheckDate;
  final String? doctor;
  final String? note;
  final bool active;
  final List<MedSlot> slots;
  final List<MedPrn> prn;

  static String _d(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'title': title,
    'start_date': _d(startDate),
    'end_date': endDate == null ? null : _d(endDate!),
    'recheck_date': recheckDate == null ? null : _d(recheckDate!),
    'doctor': doctor,
    'note': note,
    'slots': [for (final s in slots) s.toJson()],
    'prn': [for (final p in prn) p.toJson()],
  };
}

/// Tình trạng của một lần uống tại thời điểm đang xét.
enum DoseState { upcoming, due, taken, skipped, missed }

/// Một lần đến giờ uống (bảng `dose_events`).
class Dose {
  const Dose({
    required this.id,
    required this.ownerId,
    required this.label,
    required this.bag,
    required this.items,
    required this.dueAt,
    required this.windowEnd,
    required this.status,
    this.actedAt,
    this.actedBy,
    this.snoozedUntil,
  });

  factory Dose.fromJson(Map<String, dynamic> m) => Dose(
    id: m['id'] as String,
    ownerId: m['owner_id'] as String,
    label: m['slot_label'] as String,
    bag: m['mode'] != 'list',
    items: [
      for (final i in (m['items'] as List? ?? const []))
        MedItem.fromJson(Map<String, dynamic>.from(i as Map)),
    ],
    dueAt: DateTime.parse(m['due_at'] as String).toLocal(),
    windowEnd: DateTime.parse(m['window_end'] as String).toLocal(),
    status: m['status'] as String,
    actedAt: m['acted_at'] == null
        ? null
        : DateTime.parse(m['acted_at'] as String).toLocal(),
    actedBy: m['acted_by'] as String?,
    snoozedUntil: m['snoozed_until'] == null
        ? null
        : DateTime.parse(m['snoozed_until'] as String).toLocal(),
  );

  final String id;
  final String ownerId;
  final String label;
  final bool bag;
  final List<MedItem> items;
  final DateTime dueAt;
  final DateTime windowEnd;

  /// `pending`, `taken`, `skipped`, `missed`.
  final String status;
  final DateTime? actedAt;
  final String? actedBy;
  final DateTime? snoozedUntil;

  /// Cho phép bấm "Đã uống" từ 30 phút trước giờ.
  static const earlyWindow = Duration(minutes: 30);

  DoseState stateAt(DateTime now) {
    switch (status) {
      case 'taken':
        return DoseState.taken;
      case 'skipped':
        return DoseState.skipped;
      case 'missed':
        return DoseState.missed;
    }
    if (now.isAfter(windowEnd)) return DoseState.missed;
    if (now.isBefore(dueAt.subtract(earlyWindow))) return DoseState.upcoming;
    return DoseState.due;
  }

  String get hm =>
      '${dueAt.hour.toString().padLeft(2, '0')}:${dueAt.minute.toString().padLeft(2, '0')}';

  /// Mô tả ngắn thứ cần lấy: "túi Sáng" kèm thuốc nếu có liệt kê.
  String get what {
    final bagItems = items.where((i) => !i.fromJar).toList();
    final jar = items.where((i) => i.fromJar).toList();
    final b = StringBuffer(
      bag ? 'túi $label' : 'thuốc buổi ${label.toLowerCase()}',
    );
    if (bagItems.isNotEmpty)
      b.write(' (${bagItems.map((i) => i.name).join(', ')})');
    if (jar.isNotEmpty)
      b.write(', thêm từ hũ: ${jar.map((i) => i.text).join(', ')}');
    return b.toString();
  }

  /// Câu máy đọc khi đến giờ.
  String spoken(String hon) =>
      'Đến giờ uống thuốc rồi $hon ơi. $hon lấy $what nhé.';
}

/// Thống kê tuân thủ trong một khoảng: số lần uống / số lần đã đến hạn.
class Adherence {
  const Adherence({required this.taken, required this.total});

  factory Adherence.of(List<Dose> doses, DateTime now) {
    var taken = 0;
    var total = 0;
    for (final d in doses) {
      if (d.dueAt.isAfter(now)) continue;
      switch (d.stateAt(now)) {
        case DoseState.taken:
          taken++;
          total++;
        case DoseState.missed:
          total++;
        case DoseState.skipped:
        case DoseState.due:
        case DoseState.upcoming:
          break;
      }
    }
    return Adherence(taken: taken, total: total);
  }

  final int taken;
  final int total;

  double? get rate => total == 0 ? null : taken / total;
}
