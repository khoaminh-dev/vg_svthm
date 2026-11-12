import 'ocr_models.dart';

/// Tách các dòng số liệu từ văn bản OCR.
///
/// Quy tắc:
/// - Mỗi dòng có số: nhãn là chữ đứng trước số đầu tiên, đơn vị là chữ ngắn đứng sau số.
/// - Dòng chỉ có số: dùng dòng chữ ngay phía trên làm nhãn.
/// - Dòng có nhiều số (hàng của bảng): mỗi số một dòng, nhãn đánh số thứ tự.
/// - Bỏ qua ngày (12/11/2026) và giờ (10:30) để không lẫn vào số liệu.
abstract final class OcrParser {
  static final _date = RegExp(r'\b\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}\b');
  static final _time = RegExp(r'\b\d{1,2}:\d{2}(:\d{2})?\b');
  static final _number = RegExp(r'-?\d[\d.,]*');
  static final _trailingSeparators = RegExp(r'[.,]+$');
  static final _unitAfter = RegExp(r'^\s?([A-Za-zÀ-ỹ°µ%/²³]{1,6}\d?)(?![A-Za-zÀ-ỹ\d])');
  static final _labelNoise = RegExp(r'^[\s:=\-–—.|]+|[\s:=\-–—.|]+$');

  static List<OcrValue> parse(String raw) {
    final result = <OcrValue>[];
    String? pendingLabel;

    for (final original in raw.split(RegExp(r'\r?\n'))) {
      final line = original
          .replaceAll(_date, ' ')
          .replaceAll(_time, ' ')
          .trim();
      if (line.isEmpty) continue;

      final matches = _number.allMatches(line).toList();
      if (matches.isEmpty) {
        pendingLabel = _cleanLabel(line);
        continue;
      }

      final first = matches.first;
      var label = _cleanLabel(line.substring(0, first.start));
      final onlyNumbers = label.isEmpty && _cleanLabel(_removeNumbers(line)).isEmpty;
      if (label.isEmpty && onlyNumbers && pendingLabel != null) label = pendingLabel;

      // Đơn vị đứng ngay sau số (kWh, m3, kg, đ...). Số dính liền đơn vị (m3) không tính là số riêng.
      final found = <(String value, String unit)>[];
      var consumedUntil = 0;
      for (final m in matches) {
        if (m.start < consumedUntil) continue;
        final value = m.group(0)!.replaceAll(_trailingSeparators, '');
        if (value.isEmpty || value == '-') continue;
        final u = _unitAfter.firstMatch(line.substring(m.end));
        consumedUntil = u == null ? m.end : m.end + u.end;
        found.add((value, u?.group(1) ?? ''));
      }

      for (var i = 0; i < found.length; i++) {
        result.add(OcrValue(
          label: found.length > 1 && label.isNotEmpty ? '$label #${i + 1}' : label,
          value: found[i].$1,
          unit: found[i].$2,
        ));
      }
      pendingLabel = null;
    }
    return result;
  }

  static String _removeNumbers(String s) => s.replaceAll(_number, ' ');

  static String _cleanLabel(String s) => s.replaceAll(_labelNoise, '').trim();
}
