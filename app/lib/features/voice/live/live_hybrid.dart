import 'dart:math';

/// Phần thuần (không phụ thuộc Flutter/plugin, kiểm thử được) của Vy Live kiểu lai:
/// GPT-Live lo giọng nói, Vy cũ (`/api/voice/turn` đường chữ) lo chọn hàm.
/// Xem docs/PREMIUM_LIVE_DESIGN.md mục 7.

const _groups = {
  'a': 'àáạảãâầấậẩẫăằắặẳẵ',
  'e': 'èéẹẻẽêềếệểễ',
  'i': 'ìíịỉĩ',
  'o': 'òóọỏõôồốộổỗơờớợởỡ',
  'u': 'ùúụủũưừứựửữ',
  'y': 'ỳýỵỷỹ',
  'd': 'đ',
};

final Map<String, String> _fold = {
  for (final e in _groups.entries)
    for (final r in e.value.runes) String.fromCharCode(r): e.key,
};

/// Viết thường, bỏ dấu, bỏ ký tự lạ, gộp khoảng trắng. Giống `norm()` ở `api/_lib/voice/dm.ts`.
String foldVi(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    b.write(_fold[c] ?? c);
  }
  return b
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Từ khoá khẩn cấp (đã bỏ dấu). PHẢI giống `EMERGENCY` trong `api/_lib/voice/dm.ts`;
/// `test/live_hybrid_test.dart` so hai danh sách để không lệch.
const emergencyWords = [
  'dau nguc',
  'kho tho',
  'bat tinh',
  'ngat xiu',
  'te liet',
  'cap cuu',
  'chay mau',
  'nga roi',
  'tim dap nhanh',
  'bi nga',
  'toi bi te',
  'cuu toi',
  'cuu voi',
  'cuu giup',
  'sap ngat',
  'muon ngat',
  'toi sam mat',
  'tim dap manh',
  'tim dap rat nhanh',
  'khong tho duoc',
  'tho khong noi',
  'nghet tho',
  'ngop tho',
  'dau tim',
  'nhoi tim',
  'bi dot quy',
  'dau hieu dot quy',
  'mat meo',
  'meo mieng',
  'tay yeu',
  'chan yeu',
  'liet nua nguoi',
  'noi khong ro',
  'noi ngong',
  'non ra mau',
  'ho ra mau',
  'di ngoai ra mau',
  'muon chet',
  'khong muon song',
  'co nguoi nga',
  'nguoi nga',
  'bi ngat',
  'toi te',
  'bi te',
  'mat toi meo',
  'mieng toi meo',
  'tay toi yeu',
  'chan toi yeu',
  'nhoi mau co tim',
];

final RegExp _emergency = RegExp('\\b(${emergencyWords.join('|')})\\b');

/// Dò khẩn cấp ngay trong app, độc lập với model và máy chủ. Không bao giờ tự gọi hay bấm SOS.
bool looksLikeEmergency(String text) => _emergency.hasMatch(foldVi(text));

/// Khi đang chờ xác nhận gửi tin, người lớn tuổi hay nói cả câu ("bấm gửi cho bác luôn đi") chứ không
/// chỉ "gửi". Đưa câu đó về đúng một trong ba nút (Gửi/Sửa/Hủy) để máy chủ hiểu như bấm nút.
/// Trả null khi không chắc (câu dài, có vẻ là lệnh mới) → để Vy cũ tự xử lý như bình thường.
/// Thiên về an toàn: có từ phủ định hoặc "hủy/thôi" thì luôn là Hủy, không bao giờ gửi.
String? classifyConfirmReply(String text) {
  final w = foldVi(text).split(' ').where((e) => e.isNotEmpty).toList();
  if (w.isEmpty || w.length > 8) return null;
  const neg = {'khong', 'ko', 'dung', 'thoi', 'huy', 'chua', 'dut', 'bo'};
  if (w.any(neg.contains)) return 'Hủy';
  // Có nhắc nhắn tin/người nhận mới thì là lệnh mới, không phải trả lời xác nhận.
  if (w.contains('nhan') || w.contains('tin')) return null;
  if (w.contains('sua') || w.contains('doi')) return 'Sửa';
  if (w.contains('gui') || w.contains('dong') && w.contains('y')) return 'Gửi';
  return null;
}

/// Cổng xác nhận gửi tin: mã dùng một lần, có hạn, gắn với đúng nội dung đã đọc lại.
/// Hành động có ghi chỉ chạy khi cổng đang mở cho đúng nội dung đó (model không tự xác nhận được).
class ConfirmGate {
  ConfirmGate({this.ttl = const Duration(seconds: 60), DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Duration ttl;
  final DateTime Function() _now;
  final _rng = Random.secure();

  String? _code;
  String? _fingerprint;
  DateTime? _at;
  final _sent = <String, DateTime>{};

  bool get pending => _code != null && !_expired;
  String? get code => pending ? _code : null;

  bool get _expired => _at == null || _now().difference(_at!) > ttl;

  /// Mở cổng cho một việc cần xác nhận; trả về mã dùng một lần.
  String issue(String fingerprint) {
    _fingerprint = fingerprint;
    _at = _now();
    _code = List.generate(6, (_) => _rng.nextInt(16).toRadixString(16)).join();
    return _code!;
  }

  /// Dùng mã: đúng một lần, đúng nội dung, còn hạn. Gọi xong là đóng cổng.
  bool consume(String fingerprint) {
    final ok = pending && _fingerprint == fingerprint;
    clear();
    return ok;
  }

  void clear() {
    _code = null;
    _fingerprint = null;
    _at = null;
  }

  /// Khoá chống trùng: cùng một tin không gửi hai lần trong [window].
  bool firstSend(String key, {Duration window = const Duration(minutes: 2)}) {
    final now = _now();
    _sent.removeWhere((_, t) => now.difference(t) > window);
    if (_sent.containsKey(key)) return false;
    _sent[key] = now;
    return true;
  }
}

/// Độ giống giữa câu ta bảo Vy nói và câu Vy thực sự nói (0..1): tỉ lệ từ có trong câu đã nghe.
/// Dùng để đo xem GPT-Live có đọc nguyên văn không.
double sayFidelity(String say, String heard) {
  final a = foldVi(say).split(' ').where((w) => w.isNotEmpty).toList();
  if (a.isEmpty) return 1;
  final h = foldVi(heard).split(' ').toSet();
  return a.where(h.contains).length / a.length;
}

/// Gom phiên âm theo từng câu nói của người dùng.
class TranscriptBuffer {
  String _text = '';
  int lastChangeMs = -1;

  String get text => _text;
  bool get isEmpty => _text.trim().isEmpty;

  void add(String delta, int nowMs) {
    _text += delta;
    lastChangeMs = nowMs;
  }

  /// Lấy chữ và xoá để lượt sau không bị lẫn.
  String take() {
    final t = _text.trim();
    _text = '';
    lastChangeMs = -1;
    return t;
  }
}
