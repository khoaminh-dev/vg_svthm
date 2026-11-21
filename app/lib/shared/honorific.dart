/// Cách xưng hô với người dùng (bác, cô, chú, bà, ông...). Vy học và lưu ở `voice_prefs`; chữ trên màn hình
/// viết sẵn là "bác" và đi qua [hon] để đổi theo người dùng. Mặc định "bác", nên không ai đổi thì không có gì khác.
String _current = 'bác';

String get honorific => _current;

/// Đặt cách xưng hô (rỗng thì giữ "bác").
void setHonorific(String? h) {
  final t = (h ?? '').trim().toLowerCase();
  _current = t.isEmpty ? 'bác' : t;
}

final _bac = RegExp(r'(?<![\p{L}])([Bb])ác(?![\p{L}])(?!\s+sĩ)', unicode: true);

/// Thay từ "bác"/"Bác" (không phải "bác sĩ") trong [s] bằng cách xưng hô [h], giữ nguyên chữ hoa đầu câu.
String honorify(String s, String h) {
  final w = h.trim().isEmpty ? 'bác' : h.trim().toLowerCase();
  if (w == 'bác') return s;
  return s.replaceAllMapped(_bac, (m) {
    final cap = m[1] == 'B';
    return cap ? '${w[0].toUpperCase()}${w.substring(1)}' : w;
  });
}

/// Chữ trên màn hình theo cách xưng hô hiện tại.
String hon(String s) => honorify(s, _current);
