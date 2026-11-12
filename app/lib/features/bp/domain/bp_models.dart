import 'package:flutter/material.dart';

import '../../ocr/domain/ocr_models.dart';

/// Mức huyết áp theo phân loại AHA 2017 (khớp hàm `bp_category` trong DB).
enum BpCategory {
  normal('normal', 'Bình thường', Color(0xFF2E7D32)),
  elevated('elevated', 'Hơi cao', Color(0xFF9E9D24)),
  stage1('stage1', 'Tăng huyết áp độ 1', Color(0xFFEF6C00)),
  stage2('stage2', 'Tăng huyết áp độ 2', Color(0xFFD84315)),
  crisis('crisis', 'Cấp cứu: đi khám ngay', Color(0xFFB71C1C));

  const BpCategory(this.code, this.label, this.color);

  final String code;
  final String label;
  final Color color;

  static BpCategory of(int sys, int dia) {
    if (sys > 180 || dia > 120) return crisis;
    if (sys >= 140 || dia >= 90) return stage2;
    if (sys >= 130 || dia >= 80) return stage1;
    if (sys >= 120) return elevated;
    return normal;
  }
}

/// Một lần đo huyết áp.
class BpReading {
  const BpReading({
    this.id,
    required this.systolic,
    required this.diastolic,
    this.pulse,
    required this.measuredAt,
    this.source = 'ocr_ai',
    this.ocrRecordId,
    this.note,
  });

  factory BpReading.fromMap(Map<String, dynamic> m) => BpReading(
    id: m['id'] as String,
    systolic: (m['systolic'] as num).toInt(),
    diastolic: (m['diastolic'] as num).toInt(),
    pulse: (m['pulse'] as num?)?.toInt(),
    measuredAt: DateTime.parse(m['measured_at'] as String).toLocal(),
    source: (m['source'] as String?) ?? 'ocr_ai',
    ocrRecordId: m['ocr_record_id'] as String?,
    note: m['note'] as String?,
  );

  final String? id;
  final int systolic;
  final int diastolic;
  final int? pulse;
  final DateTime measuredAt;
  final String source;
  final String? ocrRecordId;
  final String? note;

  BpCategory get category => BpCategory.of(systolic, diastolic);

  /// Khớp ràng buộc của DB (tâm thu 50-300, tâm trương 30-200, tâm thu > tâm trương).
  bool get isValid =>
      systolic >= 50 &&
      systolic <= 300 &&
      diastolic >= 30 &&
      diastolic <= 200 &&
      systolic > diastolic &&
      (pulse == null || (pulse! >= 20 && pulse! <= 250));

  Map<String, dynamic> toInsert() => {
    'systolic': systolic,
    'diastolic': diastolic,
    'pulse': pulse,
    'measured_at': measuredAt.toUtc().toIso8601String(),
    'source': source,
    'ocr_record_id': ocrRecordId,
    'note': note,
  };
}

/// Tìm SYS / DIA / PULSE trong các dòng số liệu OCR.
abstract final class BpExtractor {
  static final _sys = RegExp(r'sys|systolic|t[âa]m\s*thu|tam\s*thu|t\.?\s*thu', caseSensitive: false);
  static final _dia = RegExp(r'dia|diastolic|t[âa]m\s*tr[ưu]ơng|tam\s*truong|t\.?\s*tr[ưu]ơng', caseSensitive: false);
  static final _pul = RegExp(r'pul|m[ạa]ch|nh[ịi]p|heart|bpm', caseSensitive: false);

  static BpReading? fromValues(List<OcrValue> values, {required String source, DateTime? at}) {
    int? pick(RegExp re) {
      for (final v in values) {
        if (re.hasMatch(v.label)) {
          final n = v.number;
          if (n != null) return n.round();
        }
      }
      return null;
    }

    final sys = pick(_sys);
    final dia = pick(_dia);
    if (sys == null || dia == null) return null;
    final r = BpReading(
      systolic: sys,
      diastolic: dia,
      pulse: pick(_pul),
      measuredAt: at ?? DateTime.now(),
      source: source,
    );
    return r.isValid ? r : null;
  }
}
