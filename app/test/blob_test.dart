import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/shared/blob/blob_engine.dart';
import 'package:vg_svthm/shared/blob/blob_expressions.dart';
import 'package:vg_svthm/shared/blob/blob_face.dart';
import 'package:vg_svthm/shared/blob/blob_shape.dart';
import 'package:vg_svthm/shared/blob/blob_types.dart';
import 'package:vg_svthm/shared/widgets/vy_orb.dart';

void run(BlobEngine e, double secs, {OrbMode mode = OrbMode.idle, bool awake = false, BlobMood mood = BlobMood.calm, double? level, int emphasis = 0}) {
  for (var i = 0; i < secs * 60; i++) {
    e.step(1 / 60, mode: mode, awake: awake, mood: mood, level: level, emphasis: emphasis);
  }
}

bool finite(BlobFrame f) =>
    f.points.every((p) => p.dx.isFinite && p.dy.isFinite) && f.eyes.every((e) => e.m.every((v) => v.isFinite));

void main() {
  test('16 biểu cảm, mắt đối xứng khi nhìn thẳng', () {
    expect(kExpressions.length, 16);
    final p = eyePoses(const HeadGaze(0, 0, 0));
    expect(p[0].x, closeTo(-p[1].x, 1e-9));
    expect(p[0].depth, greaterThan(0.9));
  });

  test('chuẩn hoá giữ bán kính trung bình khi méo', () {
    final out = circleProfile();
    applyWobble(out, circleProfile(), [(k: 3, amp: 0.2, phase: 0.3)]);
    expect(out.reduce((a, b) => a + b) / kSamples, closeTo(1, 1e-9));
    expect(out.reduce(math.max), greaterThan(1.05));
  });

  test('ngủ: xám, không có mắt', () {
    final e = BlobEngine();
    run(e, 2);
    final f = e.frame(200, OrbMode.idle);
    expect(f.awake, lessThan(0.05));
    expect(f.eyes, isEmpty);
    final c = f.palette.mid;
    expect((c.r - c.b).abs(), lessThan(0.1), reason: 'xám: R gần B');
    expect(finite(f), true);
  });

  test('thức: lên màu xanh, có hai mắt', () {
    final e = BlobEngine();
    run(e, 3, awake: true);
    final f = e.frame(200, OrbMode.idle);
    expect(f.awake, greaterThan(0.9));
    expect(f.eyes.length, 2);
    expect(f.palette.mid.b, greaterThan(f.palette.mid.r + 0.1));
    expect(finite(f), true);
  });

  test('cảm xúc đổi màu: khẩn cấp đỏ, vui ấm', () {
    final e = BlobEngine();
    run(e, 3, awake: true, mood: BlobMood.emergency);
    final red = e.frame(200, OrbMode.speaking).palette.top;
    expect(red.r, greaterThan(red.b + 0.3));
    run(e, 3, awake: true, mood: BlobMood.happy);
    final warm = e.frame(200, OrbMode.speaking).palette.top;
    expect(warm.r, greaterThan(warm.b));
    expect(warm.g, greaterThan(0.5));
  });

  test('khẩn cấp hiện dấu "!" và ẩn mắt', () {
    final e = BlobEngine();
    run(e, 3, awake: true, mood: BlobMood.emergency);
    final f = e.frame(200, OrbMode.speaking);
    expect(f.bang, greaterThan(0.9));
    expect(f.eyes, isEmpty);
  });

  double wobble(BlobFrame f) {
    final r = f.points.map((p) => p.distance).toList();
    return r.reduce(math.max) - r.reduce(math.min);
  }

  test('nói: thân rung theo âm lượng (to rung mạnh hơn nhỏ)', () {
    final a = BlobEngine();
    run(a, 2, mode: OrbMode.speaking, awake: true, level: 0.0);
    final quiet = wobble(a.frame(200, OrbMode.speaking));
    final b = BlobEngine();
    run(b, 2, mode: OrbMode.speaking, awake: true, level: 1.0);
    final loud = wobble(b.frame(200, OrbMode.speaking));
    expect(loud, greaterThan(quiet * 2));
  });

  test('nói mà không có số đo: dùng nhịp mô phỏng, không đứng yên', () {
    final e = BlobEngine();
    var maxW = 0.0;
    for (var i = 0; i < 180; i++) {
      e.step(1 / 60, mode: OrbMode.speaking, awake: true, mood: BlobMood.calm);
      maxW = math.max(maxW, wobble(e.frame(200, OrbMode.speaking)));
    }
    expect(maxW, greaterThan(2));
  });

  test('nghĩ: đổi dạng liên tục, hình thay đổi theo thời gian', () {
    final e = BlobEngine();
    run(e, 1, mode: OrbMode.thinking, awake: true);
    final w1 = wobble(e.frame(200, OrbMode.thinking));
    run(e, 0.8, mode: OrbMode.thinking, awake: true);
    final w2 = wobble(e.frame(200, OrbMode.thinking));
    expect((w1 - w2).abs(), greaterThan(0.3));
    run(e, 2, mode: OrbMode.idle, awake: true);
    expect(wobble(e.frame(200, OrbMode.idle)), lessThan(3), reason: 'về lại gần tròn khi hết nghĩ');
  });

  test('nhấn mạnh: có vòng sáng rồi tắt', () {
    final e = BlobEngine();
    run(e, 1, awake: true);
    run(e, 0.2, awake: true, emphasis: 1);
    expect(e.frame(200, OrbMode.idle).ringAlpha, greaterThan(0.2));
    run(e, 1.5, awake: true, emphasis: 1);
    expect(e.frame(200, OrbMode.idle).ringAlpha, 0);
  });

  testWidgets('VyOrb dựng được ở mọi trạng thái, không ném lỗi', (t) async {
    for (final m in OrbMode.values) {
      await t.pumpWidget(MaterialApp(home: Center(child: VyOrb(mode: m, awake: true, mood: BlobMood.happy, size: 120))));
      await t.pump(const Duration(milliseconds: 500));
    }
    await t.pumpWidget(const MaterialApp(home: Center(child: VyOrb(size: 56))));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(VyOrb), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('giảm chuyển động: đứng yên nhưng vẫn đúng trạng thái', (t) async {
    await t.pumpWidget(const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: MaterialApp(home: Center(child: VyOrb(awake: true, size: 100))),
    ));
    await t.pump();
    expect(find.byType(VyOrb), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
