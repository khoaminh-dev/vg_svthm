import 'bp_models.dart';

/// Nhận xét ngắn, dễ hiểu cho một lần đo (không thay thế ý kiến bác sĩ).
String bpAdvice(BpReading r, {BpReading? previous}) {
  final parts = <String>[
    switch (r.category) {
      BpCategory.normal =>
        'Huyết áp bình thường, bác cứ giữ thói quen tốt nhé.',
      BpCategory.elevated =>
        'Huyết áp hơi cao. Bác nên nghỉ ngơi, ăn nhạt và đo lại sau ít phút.',
      BpCategory.stage1 => 'Huyết áp đang cao. Bác nên nghỉ ngơi, bớt muối và theo dõi thêm vài ngày.',
      BpCategory.stage2 => 'Huyết áp cao. Bác nên nghỉ ngơi, đo lại sau 5 phút và báo người thân hoặc bác sĩ.',
      BpCategory.crisis => 'Huyết áp rất cao. Bác ngồi nghỉ, gọi người thân và đến cơ sở y tế ngay nếu thấy đau đầu, khó thở.',
    },
  ];
  final pulse = r.pulse;
  if (pulse != null && pulse > 100)
    parts.add('Mạch hơi nhanh ($pulse lần/phút).');
  if (pulse != null && pulse < 50)
    parts.add('Mạch hơi chậm ($pulse lần/phút).');
  if (previous != null) {
    final d = r.systolic - previous.systolic;
    if (d.abs() >= 10) {
      parts.add(
        d > 0
            ? 'Tâm thu cao hơn lần trước ${d.abs()} mmHg.'
            : 'Tâm thu thấp hơn lần trước ${d.abs()} mmHg.',
      );
    }
  }
  return parts.join(' ');
}
