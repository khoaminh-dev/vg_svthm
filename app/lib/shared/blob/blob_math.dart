import 'dart:math' as math;

const double tau = math.pi * 2;

double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
double lerpD(double a, double b, double t) => a + (b - a) * t;
double easeOutCubic(double t) => 1 - math.pow(1 - t, 3).toDouble();
double easeOutQuint(double t) => 1 - math.pow(1 - t, 5).toDouble();
double easeInOutCubic(double t) => t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;

/// Ease-out có độ nảy nhẹ: dùng khi mắt mở ra lúc được đánh thức.
double easeOutBack(double t) {
  const c1 = 1.70158;
  const c3 = c1 + 1;
  final x = t - 1;
  return 1 + c3 * x * x * x + c1 * x * x;
}

/// Nhiễu một chiều tuần hoàn: trôi mượt, không bao giờ lặp lại bằng mắt khi dùng chu kỳ nguyên tố.
double loopNoise(double t, double period, [double seed = 0]) {
  final p = (t / period) * tau;
  return 0.55 * math.sin(p + seed) + 0.3 * math.sin(2 * p + seed * 1.7 + 1.1) + 0.15 * math.sin(3 * p + seed * 2.3 + 2.4);
}

/// Làm mượt theo hàm mũ, độc lập tốc độ khung hình: trả về hệ số nội suy cho bước dt.
double smoothK(double dt, double rate) => 1 - math.exp(-dt * rate);
