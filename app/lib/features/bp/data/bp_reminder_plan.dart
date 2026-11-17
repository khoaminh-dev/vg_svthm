/// Logic thuần (không phụ thuộc Flutter) của lịch nhắc đo huyết áp, để dễ kiểm thử.
library;

/// Khoảng chờ trước khi nhắc lại lần duy nhất nếu chưa đo.
const bpFollowUpGap = Duration(minutes: 30);

/// Số ngày đặt trước.
const bpReminderDays = 3;

class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.at,
    required this.slot,
    required this.followUp,
  });

  /// Số thứ tự trong lịch (dùng để ghép với id thông báo).
  final int id;
  final DateTime at;

  /// 'morning' hoặc 'evening'.
  final String slot;
  final bool followUp;

  Map<String, Object?> toJson() => {
    'id': id,
    'at': at.toIso8601String(),
    'slot': slot,
    'fu': followUp,
  };

  static PlannedReminder? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = DateTime.tryParse('${j['at']}');
    if (at == null) return null;
    return PlannedReminder(
      id: (j['id'] as num?)?.toInt() ?? 0,
      at: at,
      slot: '${j['slot']}',
      followUp: j['fu'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlannedReminder &&
      other.id == id &&
      other.at == at &&
      other.slot == slot &&
      other.followUp == followUp;

  @override
  int get hashCode => Object.hash(id, at, slot, followUp);

  @override
  String toString() => '$slot${followUp ? '+30' : ''}@$at';
}

/// "HH:MM" -> số phút trong ngày, hoặc null nếu sai định dạng.
int? hmToMinutes(String? s) {
  if (s == null) return null;
  final p = s.split(':');
  if (p.length < 2) return null;
  final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
  return h * 60 + m;
}

/// [t] có nằm trong giờ yên tĩnh [start]..[end] không (qua nửa đêm cũng được; thiếu một đầu thì coi là không có).
bool inQuietHours(DateTime t, String? start, String? end) {
  final s = hmToMinutes(start), e = hmToMinutes(end);
  if (s == null || e == null || s == e) return false;
  final m = t.hour * 60 + t.minute;
  return s < e ? (m >= s && m < e) : (m >= s || m < e);
}

/// Lập lịch nhắc: mỗi giờ trong [slots] (khoá 'morning'/'evening' -> "HH:MM") của [bpReminderDays] ngày tới.
/// - Hôm nay đã đo ([measuredToday]) thì bỏ hết các lần nhắc của hôm nay.
/// - Mỗi giờ nhắc có tối đa MỘT lần nhắc lại sau [bpFollowUpGap], rồi thôi.
/// - Lần nhắc rơi vào giờ yên tĩnh thì bỏ.
/// - Chỉ giữ các lần ở tương lai.
List<PlannedReminder> planBpReminders({
  required DateTime now,
  required Map<String, String> slots,
  required bool measuredToday,
  String? quietStart,
  String? quietEnd,
  int days = bpReminderDays,
}) {
  final out = <PlannedReminder>[];
  var n = 0;
  for (var d = 0; d < days; d++) {
    if (d == 0 && measuredToday) continue;
    for (final e in slots.entries) {
      final mins = hmToMinutes(e.value);
      if (mins == null) continue;
      final base = DateTime(now.year, now.month, now.day + d, mins ~/ 60, mins % 60);
      for (final fu in const [false, true]) {
        final at = fu ? base.add(bpFollowUpGap) : base;
        final id = n++;
        if (!at.isAfter(now)) continue;
        if (inQuietHours(at, quietStart, quietEnd)) continue;
        out.add(PlannedReminder(id: id, at: at, slot: e.key, followUp: fu));
      }
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

/// Các lần nhắc trong [stored] đã đến giờ (khoảng ([since], [now]]) — coi như đã hiện ra.
List<PlannedReminder> remindersShown(
  List<PlannedReminder> stored,
  DateTime since,
  DateTime now,
) => stored.where((r) => r.at.isAfter(since) && !r.at.isAfter(now)).toList();

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
