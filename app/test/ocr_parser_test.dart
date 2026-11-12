import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/features/ocr/domain/ocr_models.dart';
import 'package:vg_svthm/features/ocr/domain/ocr_parser.dart';

void main() {
  group('parseNumber', () {
    test('kiểu Việt', () {
      expect(parseNumber('1.250.000'), 1250000);
      expect(parseNumber('36,5'), 36.5);
      expect(parseNumber('1.234,56'), 1234.56);
    });
    test('kiểu Anh', () {
      expect(parseNumber('1,250,000'), 1250000);
      expect(parseNumber('1,234.56'), 1234.56);
      expect(parseNumber('3.14'), 3.14);
    });
    test('số âm và không hợp lệ', () {
      expect(parseNumber('-12'), -12);
      expect(parseNumber('abc'), isNull);
      expect(parseNumber(''), isNull);
    });
  });

  group('OcrParser', () {
    test('nhãn: số đơn vị', () {
      final v = OcrParser.parse('Tổng tiền: 1.250.000 đ\nĐiện 125 kWh');
      expect(v.length, 2);
      expect(v[0].label, 'Tổng tiền');
      expect(v[0].value, '1.250.000');
      expect(v[0].unit, 'đ');
      expect(v[1].label, 'Điện');
      expect(v[1].value, '125');
      expect(v[1].unit, 'kWh');
    });

    test('dòng chỉ có số lấy nhãn ở dòng trên', () {
      final v = OcrParser.parse('Nhiệt độ\n36.5');
      expect(v.single.label, 'Nhiệt độ');
      expect(v.single.value, '36.5');
    });

    test('bỏ qua ngày và giờ', () {
      final v = OcrParser.parse('Ngày 12/11/2026 10:30\nHuyết áp 120');
      expect(v.single.label, 'Huyết áp');
      expect(v.single.value, '120');
    });

    test('hàng bảng có nhiều số', () {
      final v = OcrParser.parse('Cam 2 15.000 30.000');
      expect(v.map((e) => e.value), ['2', '15.000', '30.000']);
      expect(v.first.label, 'Cam #1');
    });

    test('đơn vị có số dính liền (m3) không tách thành số riêng', () {
      final v = OcrParser.parse('Nước: 18 m3');
      expect(v.length, 1);
      expect(v.single.value, '18');
      expect(v.single.unit, 'm3');
    });

    test('không có số thì rỗng', () {
      expect(OcrParser.parse('Xin chào\nkhông có gì'), isEmpty);
      expect(OcrParser.parse(''), isEmpty);
    });
  });
}
