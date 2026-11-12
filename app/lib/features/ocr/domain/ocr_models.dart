/// Một dòng số liệu tách được từ ảnh: nhãn, giá trị và đơn vị (đều là chuỗi để người dùng sửa tay).
class OcrValue {
  const OcrValue({required this.label, required this.value, this.unit = ''});

  factory OcrValue.fromJson(Map<String, dynamic> j) => OcrValue(
        label: (j['label'] ?? '') as String,
        value: (j['value'] ?? '') as String,
        unit: (j['unit'] ?? '') as String,
      );

  final String label;
  final String value;
  final String unit;

  Map<String, dynamic> toJson() => {'label': label, 'value': value, 'unit': unit};

  /// Giá trị dạng số, `null` nếu không đọc được.
  double? get number => parseNumber(value);
}

/// Kết quả một lần quét ảnh: văn bản thô và các dòng số liệu đã tách.
class OcrScan {
  const OcrScan({required this.rawText, required this.values});

  final String rawText;
  final List<OcrValue> values;
}

/// Kết quả OCR chưa lưu: ảnh trên máy, văn bản thô và các dòng số liệu.
class OcrDraft {
  const OcrDraft({
    required this.imagePath,
    required this.rawText,
    required this.values,
  });

  final String imagePath;
  final String rawText;
  final List<OcrValue> values;
}

/// Kết quả OCR đã lưu (bảng `ocr_records`).
class OcrRecord {
  const OcrRecord({
    required this.id,
    required this.title,
    required this.rawText,
    required this.values,
    required this.createdAt,
    this.imagePath,
  });

  factory OcrRecord.fromMap(Map<String, dynamic> m) => OcrRecord(
        id: m['id'] as String,
        title: (m['title'] as String?) ?? '',
        rawText: (m['raw_text'] as String?) ?? '',
        values: ((m['values'] as List<dynamic>?) ?? const [])
            .map((e) => OcrValue.fromJson(e as Map<String, dynamic>))
            .toList(),
        imagePath: m['image_path'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
      );

  final String id;
  final String title;
  final String rawText;
  final List<OcrValue> values;
  final String? imagePath;
  final DateTime createdAt;

  String get displayTitle {
    if (title.trim().isNotEmpty) return title;
    final first = values.where((v) => v.label.trim().isNotEmpty);
    return first.isEmpty ? 'Kết quả OCR' : first.first.label;
  }
}

final _thousandsDot = RegExp(r'^\d{1,3}(\.\d{3})+$');
final _thousandsComma = RegExp(r'^\d{1,3}(,\d{3})+$');

/// Đọc số theo cả kiểu Việt (1.234,5) và kiểu Anh (1,234.5). Trả về `null` nếu không phải số.
double? parseNumber(String input) {
  var s = input.trim();
  if (s.isEmpty) return null;
  final negative = s.startsWith('-');
  if (negative) s = s.substring(1);
  if (!RegExp(r'^\d[\d.,]*$').hasMatch(s)) return null;

  final hasDot = s.contains('.');
  final hasComma = s.contains(',');
  if (hasDot && hasComma) {
    // Dấu xuất hiện sau cùng là dấu thập phân.
    final decimalIsComma = s.lastIndexOf(',') > s.lastIndexOf('.');
    s = decimalIsComma
        ? s.replaceAll('.', '').replaceAll(',', '.')
        : s.replaceAll(',', '');
  } else if (hasComma) {
    s = _thousandsComma.hasMatch(s) ? s.replaceAll(',', '') : s.replaceAll(',', '.');
  } else if (hasDot) {
    if (_thousandsDot.hasMatch(s)) s = s.replaceAll('.', '');
  }

  final n = double.tryParse(s);
  if (n == null) return null;
  return negative ? -n : n;
}
