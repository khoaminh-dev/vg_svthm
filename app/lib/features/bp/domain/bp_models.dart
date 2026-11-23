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
    this.sessionId,
    this.readingNo,
    this.context = const [],
    this.restedSeconds,
    this.protocolOk,
    this.symptoms = const [],
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
    sessionId: m['session_id'] as String?,
    readingNo: (m['reading_no'] as num?)?.toInt(),
    context: _strings(m['context']),
    restedSeconds: (m['rested_seconds'] as num?)?.toInt(),
    protocolOk: m['protocol_ok'] as bool?,
    symptoms: _strings(m['symptoms']),
  );

  static List<String> _strings(Object? v) =>
      v is List ? [for (final x in v) '$x'] : const [];

  final String? id;
  final int systolic;
  final int diastolic;
  final int? pulse;
  final DateTime measuredAt;
  final String source;
  final String? ocrRecordId;
  final String? note;

  /// Phiên đo (nhiều số cách nhau 1 phút) và vị trí trong phiên.
  final String? sessionId;
  final int? readingNo;

  /// Bối cảnh trước khi đo: `woke_up`, `exertion`, `caffeine_smoke`, `rested`.
  final List<String> context;
  final int? restedSeconds;

  /// true = đã ngồi nghỉ đủ chuẩn; null = không rõ (số đo cũ), không coi là đủ chuẩn.
  final bool? protocolOk;

  /// `chest_pain`, `short_breath`, `numb_weak`, `speech_vision`, hoặc `none`.
  final List<String> symptoms;

  BpReading copyWith({String? ocrRecordId}) => BpReading(
    id: id,
    systolic: systolic,
    diastolic: diastolic,
    pulse: pulse,
    measuredAt: measuredAt,
    source: source,
    ocrRecordId: ocrRecordId ?? this.ocrRecordId,
    note: note,
    sessionId: sessionId,
    readingNo: readingNo,
    context: context,
    restedSeconds: restedSeconds,
    protocolOk: protocolOk,
    symptoms: symptoms,
  );

  BpCategory get category => BpCategory.of(systolic, diastolic);

  /// Nhãn hiển thị: số đo cao mà biết chắc chưa ngồi nghỉ đủ chuẩn thì chỉ gọi là "Số đo cao",
  /// không gắn nhãn chẩn đoán (AHA: chẩn đoán cần nhiều số đo, đo đúng cách). Mức khẩn cấp luôn giữ nguyên.
  String get displayLabel {
    final c = category;
    if (protocolOk == false &&
        (c == BpCategory.elevated || c == BpCategory.stage1 || c == BpCategory.stage2)) {
      return 'Số đo cao';
    }
    return c.label;
  }

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
    if (sessionId != null) 'session_id': sessionId,
    if (readingNo != null) 'reading_no': readingNo,
    if (context.isNotEmpty) 'context': context,
    if (restedSeconds != null) 'rested_seconds': restedSeconds,
    if (protocolOk != null) 'protocol_ok': protocolOk,
    if (symptoms.isNotEmpty) 'symptoms': symptoms,
  };

  /// Cột cũ thôi, dùng khi máy chủ chưa chạy migration 0035.
  Map<String, dynamic> toLegacyInsert() => {
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
  static final _sys = RegExp(
    r'sys|systolic|t[âa]m\s*thu|tam\s*thu|t\.?\s*thu',
    caseSensitive: false,
  );
  static final _dia = RegExp(
    r'dia|diastolic|t[âa]m\s*tr[ưu]ơng|tam\s*truong|t\.?\s*tr[ưu]ơng',
    caseSensitive: false,
  );
  static final _pul = RegExp(
    r'pul|m[ạa]ch|nh[ịi]p|heart|bpm',
    caseSensitive: false,
  );

  static BpReading? fromValues(
    List<OcrValue> values, {
    required String source,
    DateTime? at,
  }) {
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

/// Tóm tắt 7 ngày gần đây. Bỏ số đo biết chắc chưa đủ chuẩn (`protocolOk == false`); số cũ không rõ vẫn tính.
class BpWeek {
  const BpWeek({
    required this.days,
    required this.readings,
    required this.avgSys,
    required this.avgDia,
  });

  /// Số ngày khác nhau có số đo, và số lần đo được tính.
  final int days;
  final int readings;
  final int avgSys;
  final int avgDia;

  /// Cần ít nhất 3 ngày để đánh giá (AHA: tối thiểu 3, lý tưởng 7 ngày).
  static const minDays = 3;
  bool get enough => days >= minDays;
  int get daysMissing => enough ? 0 : minDays - days;
  BpCategory get category => BpCategory.of(avgSys, avgDia);

  static BpWeek? of(List<BpReading> all, DateTime now) {
    final from = now.subtract(const Duration(days: 7));
    final used = all.where((r) => r.protocolOk != false && !r.measuredAt.isBefore(from)).toList();
    if (used.isEmpty) return null;
    int avg(Iterable<int> xs) => (xs.reduce((a, b) => a + b) / xs.length).round();
    final days = {for (final r in used) '${r.measuredAt.year}-${r.measuredAt.month}-${r.measuredAt.day}'}.length;
    return BpWeek(
      days: days,
      readings: used.length,
      avgSys: avg(used.map((r) => r.systolic)),
      avgDia: avg(used.map((r) => r.diastolic)),
    );
  }
}
