import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/detection_data.dart';

enum BoxStyle { corners, full }

const _personColor = Color(0xFF378ADD);
const _pillowColor = Color(0xFFEF9F27);

Color labelColor(String label) => switch (label) {
  'person' => _personColor,
  'bed' => AppColors.levelGood,
  'pillow' => _pillowColor,
  _ => AppColors.sky,
};

String labelText(String label) => switch (label) {
  'person' => 'Người',
  'bed' => 'Giường',
  'pillow' => 'Gối',
  _ => label,
};

/// Hình chữ nhật video thực sự hiển thị trong [size] khi video giữ tỉ lệ [aspect] (có viền đen nếu lệch).
Rect videoRectIn(Size size, double aspect) {
  if (size.isEmpty || aspect <= 0) return Offset.zero & size;
  final boxAspect = size.width / size.height;
  if (boxAspect > aspect) {
    final w = size.height * aspect;
    return Rect.fromLTWH((size.width - w) / 2, 0, w, size.height);
  }
  final h = size.width / aspect;
  return Rect.fromLTWH(0, (size.height - h) / 2, size.width, h);
}

/// Vẽ khung nhận diện lên video: bốn góc hoặc đầy đủ, nhãn tiếng Việt, người có viền sáng thở nhẹ.
class DetectionPainter extends CustomPainter {
  DetectionPainter({
    required this.objects,
    required this.aspect,
    required this.style,
    required this.appear,
    required this.seconds,
    super.repaint,
  });

  final List<DetObject> Function() objects;
  final double aspect;
  final BoxStyle style;

  /// 0 = ẩn, 1 = hiện đủ (hoạt ảnh bật/tắt): vừa mờ dần vừa phóng từ 0.9 lên 1.
  final double appear;
  final double Function() seconds;

  @override
  void paint(Canvas canvas, Size size) {
    if (appear <= 0.01) return;
    final video = videoRectIn(size, aspect);
    final list = [...objects()]
      ..sort((a, b) => _order(a.label).compareTo(_order(b.label)));
    final scale = 0.9 + 0.1 * appear;
    final pulse = 0.5 + 0.5 * math.sin(seconds() * 4);
    for (final o in list) {
      final c = labelColor(o.label).withValues(alpha: appear);
      var r = Rect.fromLTWH(
        video.left + o.rect.left * video.width,
        video.top + o.rect.top * video.height,
        o.rect.width * video.width,
        o.rect.height * video.height,
      );
      final center = r.center;
      r = Rect.fromCenter(
        center: center,
        width: r.width * scale,
        height: r.height * scale,
      );
      if (o.isPerson) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(r.inflate(3), const Radius.circular(6)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..color = c.withValues(alpha: appear * (0.10 + 0.12 * pulse)),
        );
      }
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = c;
      if (style == BoxStyle.full) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(3)),
          Paint()..color = c.withValues(alpha: 0.14 * appear),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(3)),
          stroke..strokeWidth = 1.6,
        );
      } else {
        canvas.drawPath(_corners(r), stroke);
      }
      _label(canvas, r, labelText(o.label), c, o.label == 'pillow', video);
    }
  }

  static int _order(String l) => switch (l) {
    'bed' => 0,
    'pillow' => 1,
    _ => 2,
  };

  static Path _corners(Rect r) {
    final c = (math.min(r.width, r.height) / 3).clamp(6.0, 16.0);
    return Path()
      ..moveTo(r.left, r.top + c)
      ..lineTo(r.left, r.top)
      ..lineTo(r.left + c, r.top)
      ..moveTo(r.right - c, r.top)
      ..lineTo(r.right, r.top)
      ..lineTo(r.right, r.top + c)
      ..moveTo(r.right, r.bottom - c)
      ..lineTo(r.right, r.bottom)
      ..lineTo(r.right - c, r.bottom)
      ..moveTo(r.left + c, r.bottom)
      ..lineTo(r.left, r.bottom)
      ..lineTo(r.left, r.bottom - c);
  }

  void _label(
    Canvas canvas,
    Rect r,
    String text,
    Color c,
    bool darkText,
    Rect video,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: (darkText ? const Color(0xFF412402) : Colors.white)
              .withValues(alpha: c.a),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width + 10, h = tp.height + 3;
    var top = r.top - h;
    if (top < video.top) top = r.top;
    final left = r.left.clamp(video.left, math.max(video.left, video.right - w)).toDouble();
    final chip = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, w, h),
      const Radius.circular(4),
    );
    canvas.drawRRect(chip, Paint()..color = c);
    tp.paint(canvas, Offset(left + 5, top + 1.5));
  }

  @override
  bool shouldRepaint(covariant DetectionPainter old) =>
      old.style != style || old.appear != appear || old.aspect != aspect;
}
