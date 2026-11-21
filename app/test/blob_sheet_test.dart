import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/shared/blob/blob_engine.dart';
import 'package:vg_svthm/shared/blob/blob_painter.dart';
import 'package:vg_svthm/shared/blob/blob_types.dart';

// Tạo ảnh tổng hợp các trạng thái để xem bằng mắt; chỉ chạy khi đặt BLOB_SHEET=đường dẫn.
void main() {
  final out = Platform.environment['BLOB_SHEET'];
  testWidgets('tấm ảnh trạng thái Vy-Blob', (t) async {
    final cells = <(String, OrbMode, bool, BlobMood, double?, double)>[
      ('ngu', OrbMode.idle, false, BlobMood.calm, null, 3),
      ('thuc', OrbMode.idle, true, BlobMood.calm, null, 4),
      ('nghe', OrbMode.listening, true, BlobMood.calm, 0.7, 3),
      ('nghi1', OrbMode.thinking, true, BlobMood.calm, null, 1.6),
      ('nghi2', OrbMode.thinking, true, BlobMood.calm, null, 2.5),
      ('nghi3', OrbMode.thinking, true, BlobMood.calm, null, 3.4),
      ('noi', OrbMode.speaking, true, BlobMood.calm, 0.9, 3),
      ('vui', OrbMode.speaking, true, BlobMood.happy, 0.5, 4),
      ('hao hung', OrbMode.idle, true, BlobMood.excited, null, 4),
      ('to mo', OrbMode.idle, true, BlobMood.curious, null, 4),
      ('lo', OrbMode.idle, true, BlobMood.worried, null, 4),
      ('buon', OrbMode.idle, true, BlobMood.sad, null, 4),
      ('canh bao', OrbMode.speaking, true, BlobMood.alert, 0.5, 4),
      ('sos', OrbMode.speaking, true, BlobMood.emergency, 0.8, 4),
    ];
    const s = 180.0;
    await t.binding.setSurfaceSize(const Size(1300, 400));
    final key = GlobalKey();
    await t.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: key,
        child: Container(
          color: Colors.white,
          width: s * 7,
          height: s * 2,
          child: Wrap(children: [
            for (final c in cells)
              SizedBox(
                width: s,
                height: s,
                child: Builder(builder: (_) {
                  final e = BlobEngine();
                  final steps = (c.$6 * 60).round();
                  for (var i = 0; i < steps; i++) {
                    e.step(1 / 60, mode: c.$2, awake: c.$3, mood: c.$4, level: c.$5);
                  }
                  return CustomPaint(painter: BlobPainter(e.frame(s, c.$2)));
                }),
              ),
          ]),
        ),
      ),
    ));
    if (out == null) return;
    await t.runAsync(() async {
      final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 1.5);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File(out).writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
