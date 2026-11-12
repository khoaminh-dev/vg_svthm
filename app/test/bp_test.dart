import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/features/bp/domain/bp_models.dart';
import 'package:vg_svthm/features/ocr/domain/ocr_models.dart';

void main() {
  test('phân loại huyết áp theo AHA', () {
    expect(BpCategory.of(118, 78), BpCategory.normal);
    expect(BpCategory.of(125, 75), BpCategory.elevated);
    expect(BpCategory.of(135, 70), BpCategory.stage1);
    expect(BpCategory.of(118, 85), BpCategory.stage1);
    expect(BpCategory.of(128, 92), BpCategory.stage2);
    expect(BpCategory.of(185, 100), BpCategory.crisis);
  });

  test('tách SYS/DIA/PULSE từ kết quả OCR', () {
    final r = BpExtractor.fromValues(const [
      OcrValue(label: 'SYS', value: '118', unit: 'mmHg'),
      OcrValue(label: 'DIA', value: '78', unit: 'mmHg'),
      OcrValue(label: 'PULSE', value: '70', unit: '/min'),
    ], source: 'ocr_ai');
    expect(r, isNotNull);
    expect((r!.systolic, r.diastolic, r.pulse), (118, 78, 70));
    expect(r.category, BpCategory.normal);
  });

  test('nhận nhãn tiếng Việt', () {
    final r = BpExtractor.fromValues(const [
      OcrValue(label: 'Tâm thu', value: '142'),
      OcrValue(label: 'Tâm trương', value: '91'),
      OcrValue(label: 'Mạch', value: '80'),
    ], source: 'ocr_local');
    expect(r?.category, BpCategory.stage2);
  });

  test('bỏ qua khi thiếu hoặc số vô lý', () {
    expect(BpExtractor.fromValues(const [OcrValue(label: 'SYS', value: '118')], source: 'x'), isNull);
    expect(
      BpExtractor.fromValues(const [
        OcrValue(label: 'SYS', value: '70'),
        OcrValue(label: 'DIA', value: '118'),
      ], source: 'x'),
      isNull,
    );
  });
}
