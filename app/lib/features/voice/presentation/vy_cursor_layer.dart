import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/vy_cursor.dart';

const _ink = Color(0xFF101622);
const _accent = Color(0xFF0D7CFF);

/// Lớp phủ con trỏ của Vy: mũi tên bo tròn đen xanh viền trắng, nhãn nhỏ, bay theo đường cong có tăng/giảm tốc,
/// bấm có vòng sóng, và khung sáng "bác tự bấm". Không bao giờ nhận chạm (IgnorePointer).
class VyCursorLayer extends StatefulWidget {
  const VyCursorLayer({super.key});

  @override
  VyCursorLayerState createState() => VyCursorLayerState();
}

class VyCursorLayerState extends State<VyCursorLayer> with TickerProviderStateMixin implements VyCursorSurface {
  Offset _pos = Offset.zero;
  bool _visible = false;
  String _label = 'Vy';
  Rect? _glow;
  double _glowT = 0;
  double _ripple = -1;
  double _scale = 1;

  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _idle.dispose();
    super.dispose();
  }

  Future<void> _run(Duration d, Curve curve, void Function(double t) tick) async {
    if (!mounted) return;
    final c = AnimationController(vsync: this, duration: d);
    final a = CurvedAnimation(parent: c, curve: curve);
    a.addListener(() {
      if (mounted) tick(a.value);
    });
    try {
      await c.forward();
    } finally {
      a.dispose();
      c.dispose();
    }
  }

  /// Thời gian bay theo quãng đường: quãng ngắn nhanh, quãng dài tối đa 0,9 giây (kế hoạch 7.2: 600–900 ms/chặng).
  static Duration flightFor(double dist, double speed) =>
      Duration(milliseconds: ((420 + dist * 0.55).clamp(460, 900) * speed).round());

  @override
  Future<void> flyTo(Offset to, {required Offset from, String? label, bool instant = false, double speed = 1}) async {
    if (!mounted) return;
    if (!_visible) {
      setState(() {
        _pos = from;
        _visible = true;
        _scale = instant ? 1 : 0.6;
      });
      if (!instant) await _run(const Duration(milliseconds: 180), Curves.easeOut, (t) => setState(() => _scale = 0.6 + 0.4 * t));
    }
    if (label != null) setState(() => _label = label);
    final a = _pos;
    final dist = (to - a).distance;
    if (instant || dist < 2) {
      setState(() => _pos = to);
      return;
    }
    // Đường bay hơi cong (điểm điều khiển lệch ngang hướng bay), không thẳng đơ.
    final dir = (to - a) / dist;
    final perp = Offset(-dir.dy, dir.dx);
    final ctrl = Offset.lerp(a, to, 0.5)! + perp * (dist * 0.12 * (a.dx < to.dx ? 1 : -1));
    await _run(flightFor(dist, speed), Curves.easeInOutCubic, (t) {
      final u = 1 - t;
      setState(
        () => _pos = Offset(
          u * u * a.dx + 2 * u * t * ctrl.dx + t * t * to.dx,
          u * u * a.dy + 2 * u * t * ctrl.dy + t * t * to.dy,
        ),
      );
    });
  }

  @override
  Future<void> click() async {
    HapticFeedback.selectionClick();
    _run(const Duration(milliseconds: 520), Curves.easeOut, (t) => setState(() => _ripple = t)).whenComplete(() {
      if (mounted) setState(() => _ripple = -1);
    });
    await _run(const Duration(milliseconds: 110), Curves.easeIn, (t) => setState(() => _scale = 1 - 0.14 * t));
    await _run(const Duration(milliseconds: 150), Curves.easeOutBack, (t) => setState(() => _scale = 0.86 + 0.14 * t));
  }

  @override
  Future<void> glowAround(Rect r, {Duration hold = const Duration(milliseconds: 2400)}) async {
    if (!mounted) return;
    setState(() => _glow = r);
    final end = DateTime.now().add(hold);
    while (mounted && DateTime.now().isBefore(end) && _glow != null) {
      await _run(const Duration(milliseconds: 700), Curves.easeInOut, (t) => setState(() => _glowT = t));
    }
    if (mounted) setState(() => _glow = null);
  }

  @override
  Future<void> hide({bool instant = false}) async {
    if (!mounted) return;
    if (_visible && !instant) {
      await _run(const Duration(milliseconds: 160), Curves.easeIn, (t) => setState(() => _scale = 1 - 0.6 * t));
    }
    if (mounted) {
      setState(() {
        _visible = false;
        _glow = null;
        _ripple = -1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible && _glow == null) return const SizedBox.shrink();
    final size = MediaQuery.sizeOf(context);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _idle,
        builder: (context, _) {
          final breathe = 1 + 0.02 * _idle.value;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              if (_glow != null) Positioned.fill(child: CustomPaint(painter: _GlowPainter(_glow!, _glowT))),
              if (_ripple >= 0) Positioned.fill(child: CustomPaint(painter: _RipplePainter(_pos, _ripple))),
              if (_visible)
                Positioned(
                  left: _pos.dx,
                  top: _pos.dy,
                  child: Transform.scale(
                    scale: _scale * breathe,
                    alignment: Alignment.topLeft,
                    child: _CursorBody(
                      label: _label,
                      above: _pos.dy > size.height - 130,
                      left: _pos.dx > size.width - 190,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CursorBody extends StatelessWidget {
  const _CursorBody({required this.label, required this.above, required this.left});

  final String label;
  final bool above;
  final bool left;

  @override
  Widget build(BuildContext context) {
    // Nhãn nằm cạnh mũi tên, tự đổi phía để không tràn khỏi màn hình và không che nút đang chỉ.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const CustomPaint(size: Size(36, 42), painter: _ArrowPainter()),
        Positioned(
          left: left ? null : 26,
          right: left ? 14 : null,
          top: above ? -34 : 34,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _ink,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 2))],
            ),
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.2,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Mũi tên đặc bo tròn (đỉnh ở (0,0) là điểm chỉ), viền trắng, đổ bóng nhẹ: nổi được trên mọi nền.
    final path = Path()
      ..moveTo(1.5, 1.5)
      ..lineTo(1.5, 31)
      ..lineTo(8.5, 24.5)
      ..lineTo(14, 36)
      ..lineTo(19.5, 33.4)
      ..lineTo(14, 22.2)
      ..lineTo(23.5, 22.2)
      ..close();
    canvas.drawShadow(path.shift(const Offset(0, 2)), const Color(0xFF000000), 5, true);
    canvas.drawPath(path, Paint()..color = _ink);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RipplePainter extends CustomPainter {
  _RipplePainter(this.at, this.t);

  final Offset at;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final r = 12 + 48 * t;
    canvas.drawCircle(
      at,
      r,
      Paint()
        ..color = _accent.withValues(alpha: 0.5 * (1 - t))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 * (1 - t) + 1,
    );
    canvas.drawCircle(at, r * 0.6, Paint()..color = _accent.withValues(alpha: 0.16 * (1 - t)));
  }

  @override
  bool shouldRepaint(covariant _RipplePainter old) => old.t != t || old.at != at;
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.rect, this.t);

  final Rect rect;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    // "Chỉ cho bác bấm": khung dày, tương phản, thở quanh nút (không bấm).
    final pulse = 0.5 + 0.5 * math.sin(t * math.pi);
    final r = RRect.fromRectAndRadius(rect.inflate(6 + 4 * pulse), const Radius.circular(18));
    canvas.drawRRect(
      r,
      Paint()
        ..color = _accent.withValues(alpha: 0.2 + 0.14 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..color = _accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5,
    );
  }

  @override
  bool shouldRepaint(covariant _GlowPainter old) => old.t != t || old.rect != rect;
}
