import 'package:flutter/material.dart';

import '../domain/health_models.dart';

/// Nhãn ngắn + biểu tượng cho từng yếu tố (hiện dạng thẻ nhỏ thay cho đoạn chữ).
({IconData icon, String label}) factorChip(String code, RiskResult r) =>
    switch (code) {
      'bp_high_now' => (
        icon: Icons.favorite_rounded,
        label: 'Huyết áp ${r.systolic}/${r.diastolic}',
      ),
      'hypertension' => (
        icon: Icons.monitor_heart_outlined,
        label: 'Tăng huyết áp',
      ),
      'prior_stroke' => (
        icon: Icons.psychology_alt_outlined,
        label: 'Từng đột quỵ',
      ),
      'heart_disease' => (icon: Icons.heart_broken_outlined, label: 'Bệnh tim'),
      'diabetes' => (icon: Icons.water_drop_outlined, label: 'Tiểu đường'),
      'smoker' => (icon: Icons.smoking_rooms_outlined, label: 'Hút thuốc'),
      'age_65' => (icon: Icons.cake_outlined, label: 'Từ 65 tuổi'),
      _ => (icon: Icons.info_outline, label: code),
    };

/// Ba việc nên làm, mỗi việc một biểu tượng và vài chữ.
List<({IconData icon, String label})> todoFor(RiskLevel l) => switch (l) {
  RiskLevel.low => [
    (icon: Icons.favorite_border_rounded, label: 'Đo huyết áp đều'),
    (icon: Icons.directions_walk_rounded, label: 'Đi bộ nhẹ mỗi ngày'),
    (icon: Icons.restaurant_outlined, label: 'Ăn nhạt, ngủ đủ'),
  ],
  RiskLevel.attention => [
    (icon: Icons.schedule_rounded, label: 'Đo mỗi ngày, cùng giờ'),
    (icon: Icons.local_hospital_outlined, label: 'Gặp bác sĩ vài tuần tới'),
    (icon: Icons.no_food_outlined, label: 'Bớt muối, bỏ thuốc lá'),
  ],
  RiskLevel.high => [
    (icon: Icons.event_available_outlined, label: 'Đặt lịch khám sớm'),
    (icon: Icons.favorite_border_rounded, label: 'Đo và ghi mỗi ngày'),
    (icon: Icons.medication_outlined, label: 'Không tự bỏ thuốc'),
  ],
  RiskLevel.urgent => [
    (icon: Icons.event_seat_outlined, label: 'Ngồi nghỉ, đo lại'),
    (icon: Icons.local_hospital_outlined, label: 'Còn cao thì đi khám'),
    (icon: Icons.people_outline_rounded, label: 'Nhờ người thân ở cạnh'),
  ],
};

/// Câu chữ cho từng mức nguy cơ. Lời khuyên chỉ nói chuyện theo dõi, lối sống và đi khám, không nhắc đến thuốc.
String riskSentence(RiskLevel l) => switch (l) {
  RiskLevel.low =>
    'Hiện chưa thấy dấu hiệu đáng lo. Bác cứ đo huyết áp đều nhé.',
  RiskLevel.attention =>
    'Bác nên đo huyết áp đều và gặp bác sĩ trong vài tuần tới.',
  RiskLevel.high =>
    'Bác nên đi khám sớm để bác sĩ kiểm tra tim mạch và huyết áp.',
  RiskLevel.urgent => 'Huyết áp của bác đang rất cao. Nếu đau ngực, yếu liệt hoặc nói khó, gọi 115 ngay.',
};

/// Câu ngắn Vy có thể nói ra (dùng khi mức từ "cần chú ý" trở lên).
String riskSpoken(RiskLevel l) => switch (l) {
  RiskLevel.low => 'Đánh giá nguy cơ của bác đang ở mức thấp.',
  RiskLevel.attention =>
    'Bác nên theo dõi huyết áp sát hơn và gặp bác sĩ trong vài tuần tới.',
  RiskLevel.high => 'Bác nên đi khám sớm để bác sĩ kiểm tra tim mạch.',
  RiskLevel.urgent => 'Huyết áp của bác đang rất cao. Nếu bác đau ngực, yếu liệt hoặc nói khó, hãy gọi 115 ngay.',
};

/// Câu máy đọc về nguy cơ: nêu tên vấn đề ở mức đáng chú ý rồi lời khuyên; không đọc số %.
String riskSpokenDetailed(RiskResult r) {
  if (r.level == RiskLevel.urgent) return riskSpoken(r.level);
  String word(RiskLevel l) => l == RiskLevel.attention ? 'cần chú ý' : 'cao';
  final parts = <String>[
    if (r.strokeLevel.worthMentioning)
      'Nguy cơ đột quỵ ở mức ${word(r.strokeLevel)}.',
    if (r.heartLevel.worthMentioning)
      'Nguy cơ tim mạch ở mức ${word(r.heartLevel)}.',
  ];
  return [...parts, riskSpoken(r.level)].join(' ');
}

String reasonText(String code, RiskResult r) => switch (code) {
  'bp_high_now' =>
    'Huyết áp lần đo gần nhất khá cao (${r.systolic}/${r.diastolic})',
  'hypertension' => 'Bác có tăng huyết áp',
  'prior_stroke' => 'Bác từng bị đột quỵ',
  'heart_disease' => 'Bác có bệnh tim',
  'diabetes' => 'Bác có tiểu đường',
  'smoker' => 'Bác đang hút thuốc',
  'age_65' => 'Tuổi từ 65 trở lên',
  _ => code,
};

List<String> adviceFor(RiskLevel l) => switch (l) {
  RiskLevel.low => [
    'Đo huyết áp đều đặn, ít nhất vài lần mỗi tuần.',
    'Đi bộ nhẹ nhàng mỗi ngày nếu sức khoẻ cho phép.',
    'Ăn nhạt và ngủ đủ giấc.',
  ],
  RiskLevel.attention => [
    'Đo huyết áp mỗi ngày vào cùng một giờ.',
    'Hẹn gặp bác sĩ trong vài tuần tới để kiểm tra tổng quát.',
    'Hạn chế muối, bỏ thuốc lá nếu đang hút.',
  ],
  RiskLevel.high => [
    'Đặt lịch khám sớm, mang theo các số đo huyết áp.',
    'Tiếp tục đo huyết áp mỗi ngày và ghi lại.',
    'Không tự ý đổi hay bỏ thuốc đang dùng.',
  ],
  RiskLevel.urgent => [
    'Ngồi nghỉ yên và đo lại sau vài phút.',
    'Nếu vẫn rất cao hoặc thấy khó chịu, đến cơ sở y tế ngay.',
    'Nhờ người thân ở cạnh bác.',
  ],
};

const redFlags = [
  'Đau ngực hoặc khó thở',
  'Méo miệng, yếu hoặc liệt một bên người',
  'Nói khó, nói ngọng đột ngột',
  'Đau đầu dữ dội, chóng mặt hoặc nhìn mờ đột ngột',
];

const ageNote =
    'Với người trên 70 tuổi, đánh giá tim mạch có thể thấp hơn thực tế.';
const disclaimer =
    'Gợi ý tham khảo, không thay thế bác sĩ. Đây là bản thử nghiệm.';
