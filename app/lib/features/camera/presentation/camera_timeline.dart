import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/camera_events.dart';

Color levelColor(AlertLevel l) => switch (l) {
  AlertLevel.info => AppColors.sky,
  AlertLevel.watch => AppColors.levelWatch,
  AlertLevel.urgent => AppColors.levelDanger,
};

/// Dòng thời gian của clip: thanh nền, chấm sự kiện theo mức và đầu phát đỏ. Chạm hoặc kéo để tua.
class CameraTimeline extends StatelessWidget {
  const CameraTimeline({
    super.key,
    required this.duration,
    required this.events,
    required this.position,
    required this.onSeek,
  });

  final double duration;
  final List<CameraEvent> events;
  final ValueListenable<double> position;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        void seekAt(double dx) {
          if (duration <= 0) return;
          onSeek((dx / c.maxWidth).clamp(0.0, 1.0) * duration);
        }

        return Semantics(
          label: 'Dòng thời gian camera',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => seekAt(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => seekAt(d.localPosition.dx),
            child: SizedBox(
              height: 44,
              width: double.infinity,
              child: CustomPaint(
                painter: _TimelinePainter(
                  duration: duration,
                  events: events,
                  position: position,
                  track: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.duration,
    required this.events,
    required this.position,
    required this.track,
  }) : super(repaint: position);

  final double duration;
  final List<CameraEvent> events;
  final ValueListenable<double> position;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    if (duration <= 0) return;
    final y = size.height / 2;
    final bar = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, y - 4, size.width, 8),
      const Radius.circular(4),
    );
    canvas.drawRRect(bar, Paint()..color = track);
    final p = (position.value / duration).clamp(0.0, 1.0) * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, y - 4, p, 8),
        const Radius.circular(4),
      ),
      Paint()..color = AppColors.navy.withValues(alpha: 0.35),
    );
    for (final e in events) {
      final x = (e.t / duration).clamp(0.0, 1.0) * size.width;
      final r = e.level == AlertLevel.info ? 5.0 : 7.0;
      canvas.drawCircle(Offset(x, y), r + 1.5, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(x, y), r, Paint()..color = levelColor(e.level));
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(p - 1.5, 4, 3, size.height - 8),
        const Radius.circular(2),
      ),
      Paint()..color = AppColors.levelDanger,
    );
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) =>
      old.duration != duration || old.events != events || old.track != track;
}
