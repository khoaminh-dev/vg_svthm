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
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({required this.mode, required this.t, required this.level});

  final OrbMode mode;
  final double t; // 0..1 lặp mỗi 4 giây
  final double level;

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
    final body = r * 0.68 * scale;

    // Vệt sáng mờ phía sau.
    canvas.drawCircle(
      center,
      body * 1.25,
      Paint()
        ..color = AppColors.aqua.withValues(alpha: 0.28)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.22),
    );

    // Thân quả cầu: navy → xanh da trời → ngọc.
    final warm = mode == OrbMode.speaking;
    canvas.drawCircle(
      center,
      body,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 1.05,
          colors: [
            warm ? const Color(0xFFFFD9CC) : AppColors.aqua,
            AppColors.sky,
            AppColors.navy,
          ],
          stops: const [0, 0.5, 1],
        ).createShader(Rect.fromCircle(center: center, radius: body)),
    );

    // Vòng sáng xoay khi đang nghĩ.
    if (mode == OrbMode.thinking) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(t * 2 * math.pi);
      canvas.translate(-center.dx, -center.dy);
      canvas.drawCircle(
        center,
        body * 1.12,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.05
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            colors: [
              Colors.white.withValues(alpha: 0),
              AppColors.aqua,
              Colors.white.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.25, 0.5],
          ).createShader(Rect.fromCircle(center: center, radius: body * 1.12)),
      );
      canvas.restore();
    }

    // Điểm sáng bóng gương.
    canvas.drawCircle(
      center.translate(-body * 0.3, -body * 0.38),
      body * 0.16,
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.mode != mode || old.t != t || old.level != level;
}
