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
    this.highCholesterol = false,
    this.difficultyWalking = false,
    this.heightCm,
    this.weightKg,
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
  final bool? highCholesterol;
  final bool? difficultyWalking;

  /// Chiều cao (cm) và cân nặng (kg): không bắt buộc, dùng để tính BMI cho nguy cơ tiểu đường.
  final int? heightCm;
  final int? weightKg;

  bool get hasBody => heightCm != null && weightKg != null;

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
    highCholesterol: m['high_cholesterol'] as bool?,
    difficultyWalking: m['difficulty_walking'] as bool?,
    heightCm: (m['height_cm'] as num?)?.toInt(),
    weightKg: (m['weight_kg'] as num?)?.toInt(),
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
    'high_cholesterol': highCholesterol,
    'difficulty_walking': difficultyWalking,
    'height_cm': heightCm,
    'weight_kg': weightKg,
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
    bool? Function()? highCholesterol,
    bool? Function()? difficultyWalking,
    int? Function()? heightCm,
    int? Function()? weightKg,
  }) => HealthProfile(
    birthYear: birthYear ?? this.birthYear,
    sex: sex ?? this.sex,
    hypertension: hypertension != null ? hypertension() : this.hypertension,
    heartDisease: heartDisease != null ? heartDisease() : this.heartDisease,
    smoker: smoker != null ? smoker() : this.smoker,
    bpMeds: bpMeds != null ? bpMeds() : this.bpMeds,
    diabetes: diabetes != null ? diabetes() : this.diabetes,
    hadStroke: hadStroke != null ? hadStroke() : this.hadStroke,
    highCholesterol: highCholesterol != null
        ? highCholesterol()
        : this.highCholesterol,
    difficultyWalking: difficultyWalking != null
        ? difficultyWalking()
        : this.difficultyWalking,
    heightCm: heightCm != null ? heightCm() : this.heightCm,
    weightKg: weightKg != null ? weightKg() : this.weightKg,
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
    this.id,
    this.strokeP,
    this.strokeLevel = RiskLevel.low,
    this.heartP,
    this.heartLevel = RiskLevel.low,
    this.diabetesP,
    this.diabetesLevel = RiskLevel.low,
  });

  /// Nguy cơ tiểu đường (đã hiệu chỉnh); null nếu đã có tiểu đường hoặc hồ sơ chưa có chiều cao/cân nặng.
  final double? diabetesP;
  final RiskLevel diabetesLevel;

  /// Xác suất ước tính (0..1) và mức của từng mô hình; null nếu bản ghi cũ không có.
  final double? strokeP;
  final RiskLevel strokeLevel;
  final double? heartP;
  final RiskLevel heartLevel;

  /// Id lần đánh giá (bảng `health_assessments`), dùng để gắn phản hồi của người dùng.
  final String? id;
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
    String? id,
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
      id: id ?? m['id'] as String?,
      strokeP: ((m['stroke'] as Map?)?['p'] as num?)?.toDouble(),
      strokeLevel: RiskLevel.of((m['stroke'] as Map?)?['level'] as String?),
      heartP: ((m['heart'] as Map?)?['p'] as num?)?.toDouble(),
      heartLevel: RiskLevel.of((m['heart'] as Map?)?['level'] as String?),
      diabetesP: ((m['diabetes'] as Map?)?['p'] as num?)?.toDouble(),
      diabetesLevel: RiskLevel.of((m['diabetes'] as Map?)?['level'] as String?),
    );
  }
}

/// Một điểm trên biểu đồ xu hướng: xác suất ước tính của từng vấn đề tại một lần đánh giá.
class TrendPoint {
  const TrendPoint({required this.at, this.stroke, this.heart, this.diabetes});

  factory TrendPoint.fromRow(Map<String, dynamic> row) {
    final d = (row['details'] as Map?) ?? const {};
    double? p(Object? m) => ((m as Map?)?['p'] as num?)?.toDouble();
    return TrendPoint(
      at: DateTime.parse(row['created_at'] as String).toLocal(),
      stroke: (row['stroke_p'] as num?)?.toDouble() ?? p(d['stroke']),
      heart: (row['heart_p'] as num?)?.toDouble() ?? p(d['heart']),
      diabetes: p(d['diabetes']),
    );
  }

  final DateTime at;
  final double? stroke;
  final double? heart;
  final double? diabetes;
}

/// Phản hồi của người dùng cho một kết quả: `right` (đúng), `wrong` (chưa đúng), `unsure` (không rõ).
class RiskFeedback {
  const RiskFeedback({required this.verdict, this.note});

  final String verdict;
  final String? note;
}

/// Một lần bác hỏi Vy về sức khoẻ và câu Vy trả lời (bảng `health_qa`, giữ 90 ngày).
class HealthQa {
  const HealthQa({
    required this.id,
    required this.question,
    required this.answer,
    required this.askedAt,
  });

  factory HealthQa.fromMap(Map<String, dynamic> m) => HealthQa(
    id: (m['id'] as num).toInt(),
    question: m['question'] as String,
    answer: m['answer'] as String,
    askedAt: DateTime.parse(m['asked_at'] as String).toLocal(),
  );

  final int id;
  final String question;
  final String answer;
  final DateTime askedAt;
}
