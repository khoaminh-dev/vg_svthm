/// Che thông tin cá nhân trong chữ đọc từ đơn thuốc, TRÊN MÁY, trước khi gửi đi.
/// Chỉ chữ đã che mới rời máy; ảnh gốc ở lại máy.
const redactedMark = '[ĐÃ CHE]';

// Nhãn mà giá trị đi sau là thông tin cá nhân. Giữ nhãn, che phần sau.
final _labelRe = RegExp(
  r'^\s*(họ\s*(và\s*)?tên|tên\s*(bn|bệnh\s*nhân)?|bệnh\s*nhân|người\s*bệnh|bn|ngày\s*sinh|năm\s*sinh|ngày\s*tháng\s*năm\s*sinh|'
  r'địa\s*chỉ|đ\s*/\s*c|đc|nơi\s*ở|số\s*điện\s*thoại|điện\s*thoại|sđt|đt|tel|phone|'
  r'(mã|số)\s*(thẻ\s*)?(bhyt|bn|bệnh\s*nhân|hồ\s*sơ|y\s*tế|định\s*danh)|thẻ\s*bhyt|bhyt|cccd|cmnd|cmt|căn\s*cước|'
  r'người\s*(nhà|thân|giám\s*hộ)|thân\s*nhân|email|e-mail)\s*(\(.*?\))?\s*[:\-–]',
  caseSensitive: false,
  unicode: true,
);

// Nhãn đứng một mình ở cuối dòng (chữ đọc thường tách giá trị xuống dòng kế): che dòng kế tiếp.
final _labelOnlyRe = RegExp(
  r'^\s*(họ\s*(và\s*)?tên|bệnh\s*nhân|người\s*bệnh|địa\s*chỉ|ngày\s*sinh|số\s*điện\s*thoại|điện\s*thoại|sđt|'
  r'(mã|số)\s*(thẻ\s*)?(bhyt|bn|bệnh\s*nhân|hồ\s*sơ)|cccd|cmnd)\s*[:\-–]?\s*$',
  caseSensitive: false,
  unicode: true,
);

final _patterns = <RegExp>[
  // Điện thoại Việt Nam: 0xxxxxxxxx hoặc +84xxxxxxxxx, cho phép dấu cách/chấm/gạch.
  RegExp(r'(?<!\d)(\+?84|0)[\s.\-]?\d(?:[\s.\-]?\d){7,9}(?!\d)'),
  // Mã BHYT: 2 chữ cái + 13 chữ số (có thể cách nhau).
  RegExp(r'\b[A-Za-z]{2}[\s\-]?\d(?:[\s\-]?\d){12}\b'),
  // CCCD 12 số, CMND 9 số đứng riêng.
  RegExp(r'(?<!\d)\d{12}(?!\d)'),
  RegExp(r'(?<!\d)\d{9}(?!\d)'),
  // Email.
  RegExp(r'[\w.+\-]+@[\w\-]+(\.[\w\-]+)+'),
  // Tuổi và ngày sinh dạng "73 tuổi", "sinh ngày ...".
  RegExp(r'\b\d{1,3}\s*tuổi\b', caseSensitive: false, unicode: true),
  RegExp(
    r'\bsinh\s*(ngày)?\s*\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}',
    caseSensitive: false,
    unicode: true,
  ),
];

class RedactResult {
  const RedactResult(this.text, this.masked);

  /// Chữ đã che, an toàn để gửi đi.
  final String text;

  /// Số chỗ đã che (hiện cho người dùng thấy app có che).
  final int masked;
}

RedactResult redactMedText(String raw) {
  var masked = 0;
  final out = <String>[];
  var maskNext = false;
  for (final line in raw.split(RegExp(r'\r?\n'))) {
    if (maskNext && line.trim().isNotEmpty) {
      out.add(redactedMark);
      masked++;
      maskNext = false;
      continue;
    }
    maskNext = false;
    if (_labelOnlyRe.hasMatch(line)) {
      out.add(line);
      maskNext = true;
      continue;
    }
    final m = _labelRe.firstMatch(line);
    if (m != null) {
      out.add('${line.substring(0, m.end)} $redactedMark');
      masked++;
      continue;
    }
    var l = line;
    for (final p in _patterns) {
      l = l.replaceAllMapped(p, (_) {
        masked++;
        return redactedMark;
      });
    }
    out.add(l);
  }
  return RedactResult(out.join('\n'), masked);
}
