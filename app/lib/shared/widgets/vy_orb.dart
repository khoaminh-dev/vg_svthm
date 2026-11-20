import 'dart:math' as math;

import 'package:flutter/material.dart';


/// Trạng thái của quả cầu Vy.
enum OrbMode { idle, listening, thinking, speaking }

/// Quả cầu trợ lý: đổi hình theo trạng thái. Nghe: phình theo [level] (0..1); nghĩ: vòng sáng xoay;
/// nói: nhấp nhô theo nhịp; rảnh: thở chậm. Khi hệ thống bật giảm chuyển động thì đứng yên.
class VyOrb extends StatefulWidget {
  const VyOrb({
    super.key,
    this.mode = OrbMode.idle,
    this.level = 0,
    this.size = 220,
  });

  final OrbMode mode;
  final double level;
  final double size;

  @override
  State<VyOrb> createState() => _VyOrbState();
}

class _VyOrbState extends State<VyOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );
  double _smooth = 0;
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce != _still || (!reduce && !_c.isAnimating)) {
      _still = reduce;
      if (reduce) {
        _c.stop();
      } else {
        _c.repeat();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String get _label => switch (widget.mode) {
    OrbMode.idle => 'Vy đang chờ',
    OrbMode.listening => 'Vy đang nghe',
    OrbMode.thinking => 'Vy đang suy nghĩ',
    OrbMode.speaking => 'Vy đang nói',
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: _label,
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: SizedBox.square(
            dimension: widget.size,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                // Làm mượt mức âm lượng để quả cầu không giật.
                final target = widget.mode == OrbMode.listening
                    ? widget.level.clamp(0.0, 1.0)
                    : 0.0;
                _smooth += (target - _smooth) * 0.25;
                return CustomPaint(
                  painter: _OrbPainter(
                    mode: widget.mode,
                    t: _still ? 0 : _c.value,
                    level: _still ? target : _smooth,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({required this.mode, required this.t, required this.level});

  final OrbMode mode;
  final double t; // 0..1 lặp mỗi 4 giây
  final double level;

  static const _skyTop = Color(0xFF7F93FF);
  static const _skyMid = Color(0xFF9DB6FF);
  static const _skyLow = Color(0xFFDDE8FF);

  /// Mây khói xanh da trời: hình tròn phẳng, bên trong là các mảng mờ trôi chậm.
  /// Rảnh: trôi rất chậm; nghe: mây trắng dâng theo âm lượng; nghĩ: các mảng xoáy nhanh; nói: nhịp theo giọng.
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final tau = 2 * math.pi;
    final speed = switch (mode) {
      OrbMode.idle => 1.0,
      OrbMode.listening => 1.6,
      OrbMode.thinking => 3.2,
      OrbMode.speaking => 2.2,
    };
    final pulse = switch (mode) {
      OrbMode.idle => 1 + 0.02 * math.sin(t * tau),
      OrbMode.listening => 1 + 0.10 * level,
      OrbMode.thinking => 1 + 0.015 * math.sin(t * 2 * tau),
      OrbMode.speaking => 1 + 0.05 * math.sin(t * 4 * tau).abs(),
    };
    final body = r * 0.74 * pulse;
    final lift = switch (mode) {
      OrbMode.listening => 0.10 + 0.28 * level,
      OrbMode.speaking => 0.12 + 0.10 * math.sin(t * 3 * tau).abs(),
      _ => 0.06,
    };
    final a = t * tau * speed;

    // Bóng xanh mềm phía dưới, tạo cảm giác nổi.
    canvas.drawCircle(
      center + Offset(0, body * 0.18),
      body * 1.02,
      Paint()
        ..color = const Color(0xFF6F86FF).withValues(alpha: 0.30)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, body * 0.35),
    );

    final disc = Rect.fromCircle(center: center, radius: body);
    canvas.save();
    canvas.clipPath(Path()..addOval(disc));
    canvas.drawRect(
      disc,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_skyTop, _skyMid, _skyLow],
          stops: [0.0, 0.55, 1.0],
        ).createShader(disc),
    );

    void cloud(Offset at, double w, double h, Color c, double blur) {
      canvas.drawOval(
        Rect.fromCenter(center: center + at, width: w, height: h),
        Paint()
          ..color = c
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
      );
    }

    // Mảng xanh đậm phía trên, trôi vòng nhỏ.
    cloud(
      Offset(-0.22 * body + 0.10 * body * math.cos(a), -0.55 * body + 0.06 * body * math.sin(a)),
      body * 1.15,
      body * 0.85,
      const Color(0xFF6F86FF).withValues(alpha: 0.95),
      body * 0.22,
    );
    // Mảng xanh nhạt bên phải.
    cloud(
      Offset(0.50 * body + 0.08 * body * math.sin(a + 1), -0.10 * body + 0.10 * body * math.cos(a + 2)),
      body * 0.80,
      body * 0.70,
      const Color(0xFFA9C4FF).withValues(alpha: 0.92),
      body * 0.20,
    );
    // Đám mây trắng lớn ở dưới, dâng lên theo [lift].
    cloud(
      Offset(0.06 * body * math.sin(a + 3), body * (0.78 - 1.1 * lift) + 0.05 * body * math.cos(a)),
      body * 2.2,
      body * 1.15,
      Colors.white.withValues(alpha: 0.97),
      body * 0.20,
    );
    cloud(
      Offset(-0.30 * body + 0.10 * body * math.cos(a + 4), body * (0.48 - 0.9 * lift)),
      body * 0.95,
      body * 0.60,
      const Color(0xFFEAF1FF).withValues(alpha: 0.95),
      body * 0.16,
    );
    // Điểm sáng nhỏ.
    cloud(
      Offset(0.30 * body + 0.05 * body * math.sin(a * 1.3), -0.30 * body),
      body * 0.50,
      body * 0.32,
      Colors.white.withValues(alpha: 0.55),
      body * 0.12,
    );
    canvas.restore();

    // Vòng sáng mảnh khi đang nghĩ.
    if (mode == OrbMode.thinking) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(t * tau * 1.5);
      canvas.translate(-center.dx, -center.dy);
      canvas.drawCircle(
        center,
        body * 1.06,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.03
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.9),
              Colors.white.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.2, 0.45],
          ).createShader(Rect.fromCircle(center: center, radius: body * 1.06)),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.mode != mode || old.t != t || old.level != level;
}
