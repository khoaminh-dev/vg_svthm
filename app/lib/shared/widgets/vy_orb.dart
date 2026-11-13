import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

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

  /// Đường viền mềm, méo nhẹ theo thời gian: nhiều điểm trên vòng tròn, nối bằng Catmull-Rom.
  Path _blob(Offset c, double r, double phase, double wobble) {
    const n = 7;
    final pts = <Offset>[];
    for (var i = 0; i < n; i++) {
      final a = i / n * 2 * math.pi;
      final k =
          1 +
          wobble * math.sin(t * 2 * math.pi * (1 + i % 3) + phase + i * 1.7);
      pts.add(c + Offset(math.cos(a), math.sin(a)) * r * k);
    }
    final path = Path()
      ..moveTo(
        (pts[0].dx + pts[n - 1].dx) / 2,
        (pts[0].dy + pts[n - 1].dy) / 2,
      );
    for (var i = 0; i < n; i++) {
      final p = pts[i];
      final next = pts[(i + 1) % n];
      path.quadraticBezierTo(
        p.dx,
        p.dy,
        (p.dx + next.dx) / 2,
        (p.dy + next.dy) / 2,
      );
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final scale = switch (mode) {
      OrbMode.idle => 1 + 0.03 * math.sin(t * 2 * math.pi),
      OrbMode.listening => 1 + 0.22 * level,
      OrbMode.thinking => 1 + 0.02 * math.sin(t * 4 * math.pi),
      OrbMode.speaking => 1 + 0.07 * math.sin(t * 8 * math.pi).abs(),
    };
    final wobble = switch (mode) {
      OrbMode.idle => 0.11,
      OrbMode.listening => 0.1 + 0.12 * level,
      OrbMode.thinking => 0.13,
      OrbMode.speaking => 0.15,
    };
    final body = r * 0.62 * scale;
    final warm = mode == OrbMode.speaking;

    // Quầng sáng lan toả phía sau.
    canvas.drawCircle(
      center,
      body * 1.35,
      Paint()
        ..color = AppColors.sky.withValues(alpha: 0.32)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.3),
    );

    // Ba lớp màu mềm chồng lên nhau, mỗi lớp méo theo nhịp riêng.
    void layer(
      Offset shift,
      double k,
      double phase,
      List<Color> colors,
      double blur,
    ) {
      final c = center + shift * body;
      final path = _blob(c, body * k, phase, wobble);
      canvas.drawPath(
        path,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.4),
            radius: 1.0,
            colors: colors,
          ).createShader(Rect.fromCircle(center: c, radius: body * k * 1.1))
          ..maskFilter = blur > 0
              ? MaskFilter.blur(BlurStyle.normal, blur)
              : null,
      );
    }

    final o = math.sin(t * 2 * math.pi);
    final q = math.cos(t * 2 * math.pi);
    layer(Offset.zero, 1.0, 0, [AppColors.sky, AppColors.navy], 0);
    layer(Offset(0.28 * o, 0.18 * q), 0.78, 2, [
      warm ? const Color(0xFFFFC9B8) : AppColors.aqua,
      AppColors.aqua.withValues(alpha: 0),
    ], r * 0.05);
    layer(Offset(-0.3 * q, 0.25 * o), 0.7, 4, [
      const Color(0xFFA78BFF),
      const Color(0x00A78BFF),
    ], r * 0.07);
    layer(Offset(0.1 * q, -0.3 * o), 0.4, 5, [
      Colors.white.withValues(alpha: 0.7),
      const Color(0x00FFFFFF),
    ], r * 0.09);

    // Vòng sáng xoay khi đang nghĩ.
    if (mode == OrbMode.thinking) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(t * 2 * math.pi);
      canvas.translate(-center.dx, -center.dy);
      canvas.drawCircle(
        center,
        body * 1.18,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.04
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            colors: [
              Colors.white.withValues(alpha: 0),
              AppColors.aqua,
              Colors.white.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.25, 0.5],
          ).createShader(Rect.fromCircle(center: center, radius: body * 1.18)),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.mode != mode || old.t != t || old.level != level;
}
