import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Hồ sơ sức khoẻ nhập một lần. `null` ở các câu có/không nghĩa là "không rõ".
class HealthProfile {
  const HealthProfile({
    required this.birthYear,
    required this.sex,
    this.hypertension = false,
    this.heartDisease = false,
    this.smoker = false,
    this.bpMeds = false,
    this.diabetes = false,
    this.hadStroke = false,
  });

  final int birthYear;

  /// `male` hoặc `female`.
  final String sex;
  final bool? hypertension;
  final bool? heartDisease;
  final bool? smoker;
  final bool? bpMeds;
  final bool? diabetes;
  final bool? hadStroke;

  int ageAt(DateTime now) => now.year - birthYear;

  factory HealthProfile.fromMap(Map<String, dynamic> m) => HealthProfile(
    birthYear: (m['birth_year'] as num).toInt(),
    sex: m['sex'] as String,
    hypertension: m['has_hypertension'] as bool?,
    heartDisease: m['has_heart_disease'] as bool?,
    smoker: m['is_smoker'] as bool?,
    bpMeds: m['on_bp_meds'] as bool?,
    diabetes: m['has_diabetes'] as bool?,
    hadStroke: m['had_stroke'] as bool?,
  );

  Map<String, dynamic> toUpsert() => {
    'birth_year': birthYear,
    'sex': sex,
    'has_hypertension': hypertension,
    'has_heart_disease': heartDisease,
    'is_smoker': smoker,
    'on_bp_meds': bpMeds,
    'has_diabetes': diabetes,
    'had_stroke': hadStroke,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  HealthProfile copyWith({
    int? birthYear,
    String? sex,
    bool? Function()? hypertension,
    bool? Function()? heartDisease,
    bool? Function()? smoker,
    bool? Function()? bpMeds,
    bool? Function()? diabetes,
    bool? Function()? hadStroke,
  }) => HealthProfile(
    birthYear: birthYear ?? this.birthYear,
    sex: sex ?? this.sex,
    hypertension: hypertension != null ? hypertension() : this.hypertension,
    heartDisease: heartDisease != null ? heartDisease() : this.heartDisease,
    smoker: smoker != null ? smoker() : this.smoker,
    bpMeds: bpMeds != null ? bpMeds() : this.bpMeds,
    diabetes: diabetes != null ? diabetes() : this.diabetes,
    hadStroke: hadStroke != null ? hadStroke() : this.hadStroke,
  );
}

/// Mức nguy cơ hiển thị cho người dùng (đã gộp từ hai model và luật huyết áp).
enum RiskLevel {
  low('low', 'Thấp', AppColors.levelGood),
  attention('attention', 'Cần chú ý', AppColors.levelWatch),
  high('high', 'Cao', AppColors.levelHigh),
  urgent('urgent', 'Cần đi khám ngay', AppColors.levelDanger);

  const RiskLevel(this.code, this.label, this.color);

  final String code;
  final String label;
  final Color color;

  static RiskLevel of(String? code) => RiskLevel.values.firstWhere(
    (l) => l.code == code,
    orElse: () => RiskLevel.low,
  );

  /// Từ "Cần chú ý" trở lên mới đáng nói ra ngay ở màn đo, mức thấp chỉ hiện nhẹ ở Trang chủ.
  bool get worthMentioning => index >= RiskLevel.attention.index;
}

/// Kết quả một lần đánh giá (từ API hoặc đọc lại từ bảng `health_assessments`).
class RiskResult {
  const RiskResult({
    required this.level,
    required this.reasons,
    required this.systolic,
    required this.diastolic,
    required this.measuredAt,
    required this.createdAt,
    this.ageOutOfRange = false,
    this.hypertensionDerived = false,
  });

  final RiskLevel level;

  /// Mã lý do (xem `risk_texts.dart`).
  final List<String> reasons;
  final int systolic;
  final int diastolic;
  final DateTime measuredAt;
  final DateTime createdAt;

  /// Người trên 70 tuổi: model tim mạch chỉ huấn luyện đến 70 nên có thể đánh giá thấp.
  final bool ageOutOfRange;
  final bool hypertensionDerived;

  /// Từ JSON của API hoặc cột `details` của bảng (cùng cấu trúc).
  factory RiskResult.fromJson(
    Map<String, dynamic> m, {
    String? level,
    String? createdAt,
  }) {
    final bp = m['bp'] as Map<String, dynamic>;
    return RiskResult(
      level: RiskLevel.of(level ?? m['level'] as String?),
      reasons: [
        for (final r in (m['reasons'] as List? ?? const [])) r as String,
      ],
      systolic: (bp['systolic'] as num).toInt(),
      diastolic: (bp['diastolic'] as num).toInt(),
      measuredAt: DateTime.parse(bp['measuredAt'] as String).toLocal(),
      createdAt: DateTime.parse((createdAt ?? m['createdAt']) as String)
          .toLocal(),
      ageOutOfRange: m['ageOutOfRange'] as bool? ?? false,
      hypertensionDerived: m['hypertensionDerived'] as bool? ?? false,
    );
  }
}
