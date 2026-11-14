import '../domain/health_models.dart';

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
