import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'brand_paths.dart';

/// Đọc đường nét SVG chỉ gồm lệnh tuyệt đối M, L, C, Z (đủ cho logo đã dò nét).
ui.Path parseBrandPath(String d) {
  final path = ui.Path();
  final tokens = RegExp(r'([MLCZ])|(-?\d+\.?\d*)').allMatches(d).map((m) => m.group(0)!).toList();
  var i = 0;
  double n() => double.parse(tokens[i++]);
  String cmd = 'M';
  while (i < tokens.length) {
    final t = tokens[i];
    if (RegExp(r'[MLCZ]').hasMatch(t)) {
      cmd = t;
      i++;
      if (cmd == 'Z') {
        path.close();
        continue;
      }
    }
    switch (cmd) {
      case 'M':
        path.moveTo(n(), n());
        cmd = 'L'; // các cặp số sau M liền là L
      case 'L':
        path.lineTo(n(), n());
      case 'C':
        path.cubicTo(n(), n(), n(), n(), n(), n());
    }
  }
  path.fillType = ui.PathFillType.evenOdd;
  return path;
}

class _BrandShapes {
  _BrandShapes()
    : swoosh = parseBrandPath(brandSwoosh),
      cross = parseBrandPath(brandCross),
      cyan = parseBrandPath(brandCyanPart),
      word = parseBrandPath(brandWordmark),
      tag = parseBrandPath(brandTagline);

  final ui.Path swoosh;
  final ui.Path cross;
  final ui.Path cyan;
  final ui.Path word;
  final ui.Path tag;

  static final _BrandShapes instance = _BrandShapes();
}

double _seg(double t, double a, double b, [Curve curve = Curves.linear]) {
  if (t <= a) return 0;
  if (t >= b) return 1;
  return curve.transform((t - a) / (b - a));
}

/// Vẽ logo theo tiến độ [t] từ 0 đến 1: vòng cung quét ra, chữ thập bật lên, nửa ngọc trượt vào,
/// chữ VIEGRAND quét từ trái sang phải, dòng phụ hiện dần. Khi t = 1 là đúng logo gốc.
class BrandLogoPainter extends CustomPainter {
  BrandLogoPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final s = _BrandShapes.instance;
    final k = math.min(size.width / brandViewW, size.height / brandViewH);
    canvas.save();
    canvas.translate((size.width - brandViewW * k) / 2, (size.height - brandViewH * k) / 2);
    canvas.scale(k);

    final navy = Paint()..color = const Color(brandNavy)..isAntiAlias = true;
    final cyan = Paint()..color = const Color(brandCyan)..isAntiAlias = true;
    final ink = Paint()..color = const Color(brandInk)..isAntiAlias = true;

    // 1) Vòng cung: quét ngược chiều kim đồng hồ từ đỉnh, giống nét bút vẽ ra.
    final sw = _seg(t, 0.00, 0.40, Curves.easeInOutCubic);
    if (sw > 0) {
      const c = Offset(415, 300);
      final clip = ui.Path()
        ..moveTo(c.dx, c.dy)
        ..arcTo(Rect.fromCircle(center: c, radius: 900), -math.pi / 2, -4.5 * sw, false)
        ..close();
      canvas.save();
      canvas.clipPath(clip);
      canvas.drawPath(s.swoosh, navy);
      canvas.restore();
    }

    // 2) Chữ thập xanh đậm: phóng lên có nảy nhẹ.
    final cr = _seg(t, 0.26, 0.52, Curves.easeOutBack);
    if (cr > 0) {
      const c = Offset(397, 271);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(0.55 + 0.45 * cr);
      canvas.translate(-c.dx, -c.dy);
      final a = _seg(t, 0.26, 0.40).clamp(0.0, 1.0);
      canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: a));
      canvas.drawPath(s.cross, navy);
      canvas.restore();
      canvas.restore();
    }

    // 3) Nửa ngọc: trượt từ dưới phải lên và hiện dần.
    final cy = _seg(t, 0.40, 0.66, Curves.easeOutCubic);
    if (cy > 0) {
      canvas.save();
      canvas.translate(26 * (1 - cy), 34 * (1 - cy));
      canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: cy));
      canvas.drawPath(s.cyan, cyan);
      canvas.restore();
      canvas.restore();
    }

    // 4) Chữ VIEGRAND: quét từ trái sang phải, hơi trồi lên.
    final wd = _seg(t, 0.52, 0.86, Curves.easeInOutCubic);
    if (wd > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(60, 540, (brandViewW - 60) * wd, 160));
      canvas.translate(0, 22 * (1 - wd));
      canvas.drawPath(s.word, ink);
      canvas.restore();
    }

    // 5) Dòng phụ: hiện dần.
    final tg = _seg(t, 0.80, 1.00, Curves.easeOut);
    if (tg > 0) {
      canvas.save();
      canvas.translate(0, 10 * (1 - tg));
      canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: tg));
      canvas.drawPath(s.tag, ink);
      canvas.restore();
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(BrandLogoPainter old) => old.t != t;
}

/// Logo Viegrand (đứng yên, đủ chi tiết) vẽ bằng đường nét, sắc ở mọi kích cỡ.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.width = 240});

  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: width * brandViewH / brandViewW,
    child: CustomPaint(painter: BrandLogoPainter(1)),
  );
}

/// Lớp phủ mở đầu: logo chuyển động trên nền trắng khi app vừa mở, rồi mờ dần để lộ màn hình bên dưới.
/// Chỉ chạy một lần mỗi lần mở app. Chạm để bỏ qua. Người dùng tắt hiệu ứng chuyển động thì không chạy.
class LogoIntro extends StatefulWidget {
  const LogoIntro({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  /// Đã chạy trong lần mở app này chưa (đặt lại để kiểm thử).
  static bool played = false;

  @override
  State<LogoIntro> createState() => _LogoIntroState();
}

class _LogoIntroState extends State<LogoIntro> with TickerProviderStateMixin {
  static const _drawMs = 2300;
  static const _holdMs = 450;
  static const _fadeMs = 380;

  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _drawMs),
  );
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _fadeMs),
  );
  bool _active = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!widget.enabled || LogoIntro.played || reduce) return;
    LogoIntro.played = true;
    _active = true;
    _run();
  }

  Future<void> _run() async {
    try {
      await _draw.forward().orCancel;
      await Future<void>.delayed(const Duration(milliseconds: _holdMs));
      if (!mounted) return;
      await _finish();
    } on TickerCanceled {
      // thoát màn hình giữa chừng
    }
  }

  Future<void> _finish() async {
    if (!_active || _fade.isAnimating || _fade.isCompleted) return;
    _draw.value = 1;
    await _fade.forward().orCancel;
    if (mounted) setState(() => _active = false);
  }

  @override
  void dispose() {
    _draw.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_active) return widget.child;
    final size = MediaQuery.sizeOf(context);
    final w = math.min(size.width * 0.78, 400.0);
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        Positioned.fill(
          child: FadeTransition(
            opacity: ReverseAnimation(_fade),
            child: GestureDetector(
              key: const Key('logo-intro'),
              behavior: HitTestBehavior.opaque,
              onTap: _finish,
              child: ColoredBox(
                color: Colors.white,
                child: Center(
                  child: Semantics(
                    label: 'Viegrand',
                    child: AnimatedBuilder(
                      animation: _draw,
                      builder: (context, _) => SizedBox(
                        width: w,
                        height: w * brandViewH / brandViewW,
                        child: CustomPaint(painter: BrandLogoPainter(_draw.value)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
