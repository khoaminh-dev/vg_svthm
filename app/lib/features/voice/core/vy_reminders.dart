/// Nhắc chủ động của Vy (kế hoạch mục 9.3, quyết định D19): Vy tự mở panel khi có việc cần nhắc, bằng động cơ miễn phí
/// (Vy thường, giọng máy), KHÔNG mở Live. File này chỉ chứa phần QUYẾT ĐỊNH, thuần (không đụng giao diện/mạng) để kiểm thử bằng chữ.
library;

/// Loại nhắc, theo thứ tự ưu tiên giảm dần: thuốc > đo huyết áp > tin nhắn (SOS/khẩn cấp luôn thắng và chặn mọi nhắc).
enum ReminderKind { dose, bp, messages }

/// Khoảng cách tối thiểu giữa hai lần nhắc tin nhắn.
const messageGap = Duration(minutes: 15);

/// "Để sau" cho tin nhắn chỉ được nhắc lại tối đa chừng này lần.
const maxLater = 1;

/// Cửa sổ sau giờ nhắc đo huyết áp mà còn được nhắc (quá thì thôi, đỡ phiền).
const bpWindow = Duration(hours: 3);

/// Một việc cần nhắc đã được chọn.
class ReminderPick {
  const ReminderPick(this.kind, this.key);

  final ReminderKind kind;

  /// Mã chống nhắc lặp: cùng mã thì chỉ nhắc một lần.
  final String key;

  @override
  String toString() => '${kind.name}:$key';
}

/// Tin nhắn mới đến (đã gom theo phòng) để cân nhắc việc nhắc.
class NewMessages {
  const NewMessages({required this.roomId, required this.from, required this.count, required this.latest});

  final String roomId;
  final String from;
  final int count;
  final DateTime latest;
}

/// Việc đến hạn nhắc hôm nay của huyết áp.
class BpDue {
  const BpDue({required this.slot, required this.key});

  /// "morning" hoặc "evening".
  final String slot;
  final String key;
}

/// Ảnh chụp tình hình ở một nhịp kiểm tra.
class ReminderInputs {
  const ReminderInputs({
    required this.now,
    required this.foreground,
    required this.busy,
    this.enabledDose = true,
    this.enabledBp = true,
    this.enabledMessages = true,
    this.quiet = false,
    this.doseKey,
    this.bpDue,
    this.messages = const [],
  });

  final DateTime now;

  /// App đang ở nền trước. Nền sau/khoá màn hình thì dùng thông báo/báo thức có sẵn, không tự mở Vy.
  final bool foreground;

  /// Đang bận: Vy đang mở (kể cả Live), khẩn cấp/SOS, đang gọi, đang đo huyết áp, con trỏ đang chạy...
  final bool busy;

  final bool enabledDose;
  final bool enabledBp;
  final bool enabledMessages;

  /// Trong giờ yên tĩnh: chặn nhắc không quan trọng, KHÔNG chặn thuốc (quyết định D3).
  final bool quiet;

  /// Cữ thuốc đang đến giờ (mã `dose:<id>:<mốc hoãn>`), null nếu không có.
  final String? doseKey;

  final BpDue? bpDue;
  final List<NewMessages> messages;
}

/// Trí nhớ của bộ nhắc (trong một lần chạy app): cái gì đã nhắc, lần nhắc tin nhắn gần nhất, số lần "để sau".
class ReminderMemory {
  final done = <String>{};
  final laterCount = <String, int>{};
  DateTime? lastMessages;

  /// Lúc đã nhắc từng việc (để nhớ qua lần mở lại app, tránh nhắc lặp cùng một việc).
  final _shownAt = <String, int>{};

  /// Giữ lại bao lâu thì quên (việc nhắc đã cũ, khoá của nó cũng không còn xuất hiện nữa).
  static const keep = Duration(hours: 36);

  void markShown(ReminderPick p, DateTime now) {
    done.add(p.key);
    _shownAt[p.key] = now.millisecondsSinceEpoch;
    if (p.kind == ReminderKind.messages) lastMessages = now;
  }

  /// Ảnh chụp để lưu trên máy: chỉ các việc đã nhắc chưa quá [keep].
  Map<String, int> snapshot(DateTime now) => {
    for (final e in _shownAt.entries)
      if (done.contains(e.key) && now.millisecondsSinceEpoch - e.value < keep.inMilliseconds) e.key: e.value,
  };

  /// Nạp lại những việc đã nhắc ở lần chạy trước (bỏ cái quá hạn).
  void restore(Map<String, int> saved, DateTime now) {
    for (final e in saved.entries) {
      if (now.millisecondsSinceEpoch - e.value >= keep.inMilliseconds) continue;
      done.add(e.key);
      _shownAt[e.key] = e.value;
    }
  }

  /// Người dùng chọn "Để sau" ở nhắc tin nhắn: cho phép nhắc lại một lần (sau [messageGap]).
  bool later(ReminderPick p) {
    final n = laterCount[p.key] ?? 0;
    if (n >= maxLater) return false;
    laterCount[p.key] = n + 1;
    done.remove(p.key);
    _shownAt.remove(p.key);
    return true;
  }
}

/// Chọn việc cần nhắc (hoặc null). Thứ tự: thuốc > đo huyết áp > tin nhắn.
ReminderPick? decideReminder(ReminderInputs i, ReminderMemory mem) {
  if (!i.foreground || i.busy) return null;

  final dk = i.doseKey;
  if (i.enabledDose && dk != null && !mem.done.contains(dk)) {
    return ReminderPick(ReminderKind.dose, dk);
  }

  final bp = i.bpDue;
  if (i.enabledBp && !i.quiet && bp != null && !mem.done.contains(bp.key)) {
    return ReminderPick(ReminderKind.bp, bp.key);
  }

  if (i.enabledMessages && !i.quiet && i.messages.isNotEmpty) {
    final last = mem.lastMessages;
    if (last == null || i.now.difference(last) >= messageGap) {
      for (final m in i.messages) {
        final key = 'msg:${m.roomId}:${m.latest.millisecondsSinceEpoch}';
        if (!mem.done.contains(key)) return ReminderPick(ReminderKind.messages, key);
      }
    }
  }
  return null;
}

// ---------------------------------------------------------------- các hàm thuần phụ trợ

/// Đang trong giờ yên tĩnh [start]–[end] ("22:00"–"06:00", qua nửa đêm được). Thiếu một đầu thì không yên tĩnh.
bool inQuietHours(DateTime now, String? start, String? end) {
  if (start == null || end == null) return false;
  int? m(String s) {
    final p = s.split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]), mi = int.tryParse(p[1]);
    return h == null || mi == null ? null : h * 60 + mi;
  }

  final a = m(start), b = m(end);
  if (a == null || b == null || a == b) return false;
  final t = now.hour * 60 + now.minute;
  return a < b ? (t >= a && t < b) : (t >= a || t < b);
}

/// Mã cữ thuốc để chống nhắc lặp: cùng cữ nhưng đã hoãn (giờ hoãn khác) thì là lần nhắc mới.
String doseReminderKey(String doseId, DateTime? snoozedUntil) => 'dose:$doseId:${snoozedUntil?.millisecondsSinceEpoch ?? 0}';

/// Cữ thuốc có được nhắc lúc [now] không: đã đến giờ uống (không nhắc sớm 30 phút như cửa sổ "bấm Đã uống"), chưa quá cửa sổ,
/// và nếu đang hoãn thì phải hết hoãn.
bool doseIsDueForReminder({
  required DateTime now,
  required DateTime dueAt,
  required DateTime windowEnd,
  required bool pending,
  DateTime? snoozedUntil,
}) {
  if (!pending) return false;
  if (now.isBefore(dueAt) || now.isAfter(windowEnd)) return false;
  if (snoozedUntil != null && now.isBefore(snoozedUntil)) return false;
  return true;
}

/// Giờ nhắc đo huyết áp hôm nay đã đến mà CHƯA đo (kể từ 1 giờ trước giờ nhắc) và còn trong [bpWindow]; null nếu không.
/// [slots] dạng {"morning": "08:00", "evening": "19:00"}; [measured] là các lần đo gần nhất.
BpDue? bpReminderDue(DateTime now, Map<String, String> slots, List<DateTime> measured) {
  BpDue? best;
  DateTime? bestAt;
  for (final e in slots.entries) {
    final p = e.value.split(':');
    if (p.length < 2) continue;
    final h = int.tryParse(p[0]), mi = int.tryParse(p[1]);
    if (h == null || mi == null) continue;
    final at = DateTime(now.year, now.month, now.day, h, mi);
    if (now.isBefore(at) || now.isAfter(at.add(bpWindow))) continue;
    final since = at.subtract(const Duration(hours: 1));
    if (measured.any((t) => !t.isBefore(since))) continue; // đã đo quanh giờ đó
    if (bestAt == null || at.isAfter(bestAt)) {
      bestAt = at;
      best = BpDue(slot: e.key, key: 'bp:${now.year}-${now.month}-${now.day}:${e.key}');
    }
  }
  return best;
}

/// Gom tin nhắn mới theo phòng: chỉ tin đến SAU [since] (lúc mở app/lần nhắc trước), bỏ phòng đang mở. Mới nhất trước.
List<NewMessages> groupNewMessages(
  List<({String roomId, String from, DateTime at})> incoming, {
  required DateTime since,
  String? openRoomId,
}) {
  final byRoom = <String, List<({String roomId, String from, DateTime at})>>{};
  for (final m in incoming) {
    if (!m.at.isAfter(since)) continue;
    if (m.roomId == openRoomId) continue;
    (byRoom[m.roomId] ??= []).add(m);
  }
  final out = [
    for (final e in byRoom.entries)
      NewMessages(
        roomId: e.key,
        from: e.value.first.from,
        count: e.value.length,
        latest: e.value.map((m) => m.at).reduce((a, b) => a.isAfter(b) ? a : b),
      ),
  ]..sort((a, b) => b.latest.compareTo(a.latest));
  return out;
}

/// Câu Vy nói khi nhắc (giọng máy). [hon] là cách xưng hô ("bác").
String reminderSpeech(ReminderKind kind, String hon, {String? doseWhat, String? from, int count = 1}) {
  switch (kind) {
    case ReminderKind.dose:
      return 'Đến giờ uống thuốc rồi $hon ơi.${doseWhat == null ? '' : ' $hon lấy $doseWhat nhé.'}';
    case ReminderKind.bp:
      return 'Đến giờ đo huyết áp rồi $hon ơi.';
    case ReminderKind.messages:
      return count > 1
          ? '$hon có $count tin mới từ ${from ?? 'người thân'}. $hon muốn nghe không ạ?'
          : '$hon có tin mới từ ${from ?? 'người thân'}. $hon muốn nghe không ạ?';
  }
}
