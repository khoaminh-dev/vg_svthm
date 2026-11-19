import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/features/voice/live/live_hybrid.dart';

void main() {
  test('foldVi bỏ dấu, chữ thường, gộp khoảng trắng', () {
    expect(foldVi('  Đau   NGỰC, quá! '), 'dau nguc qua');
    expect(foldVi('Nhắn cho con trai'), 'nhan cho con trai');
  });

  test('looksLikeEmergency dò từ khoá khẩn cấp, không dò nhầm câu thường', () {
    expect(looksLikeEmergency('Tôi bị đau ngực quá'), isTrue);
    expect(looksLikeEmergency('bác khó thở'), isTrue);
    expect(looksLikeEmergency('bác vừa ngã rồi'), isTrue);
    expect(looksLikeEmergency('mở huyết áp cho bác'), isFalse);
    expect(looksLikeEmergency('nhắn cho con trai là mai bác về'), isFalse);
  });

  test('danh sách khẩn cấp ở Dart giống hệt EMERGENCY trong api/_lib/voice/dm.ts', () {
    final src = File('../api/_lib/voice/dm.ts').readAsStringSync();
    final m = RegExp(r'const EMERGENCY = /\\b\(([^)]*)\)\\b/').firstMatch(src);
    expect(m, isNotNull, reason: 'không tìm thấy EMERGENCY trong dm.ts');
    expect(m!.group(1)!.split('|'), emergencyWords);
  });

  group('ConfirmGate', () {
    test('mã dùng một lần, đúng nội dung', () {
      final g = ConfirmGate();
      expect(g.pending, isFalse);
      expect(g.consume('a'), isFalse); // chưa mở thì không dùng được
      final code = g.issue('send|room1|Mai bác về');
      expect(code, hasLength(6));
      expect(g.pending, isTrue);
      expect(g.consume('send|room1|noi dung khac'), isFalse); // sai nội dung → đóng luôn
      expect(g.pending, isFalse);

      g.issue('send|room1|Mai bác về');
      expect(g.consume('send|room1|Mai bác về'), isTrue);
      expect(g.consume('send|room1|Mai bác về'), isFalse); // dùng lần hai bị từ chối
    });

    test('hết hạn thì không dùng được', () {
      var t = DateTime(2026, 11, 19, 10);
      final g = ConfirmGate(ttl: const Duration(seconds: 60), now: () => t);
      g.issue('x');
      t = t.add(const Duration(seconds: 61));
      expect(g.pending, isFalse);
      expect(g.consume('x'), isFalse);
    });

    test('mở cổng mới thay mã cũ', () {
      final g = ConfirmGate();
      g.issue('a');
      g.issue('b');
      expect(g.consume('a'), isFalse);
    });

    test('firstSend chặn gửi trùng trong 2 phút', () {
      var t = DateTime(2026, 11, 19, 10);
      final g = ConfirmGate(now: () => t);
      expect(g.firstSend('k'), isTrue);
      expect(g.firstSend('k'), isFalse);
      t = t.add(const Duration(minutes: 3));
      expect(g.firstSend('k'), isTrue);
    });
  });

  test('sayFidelity đo mức đọc đúng nguyên văn', () {
    expect(sayFidelity('Dạ, con gửi rồi ạ.', 'Dạ con gửi rồi ạ'), 1);
    expect(sayFidelity('Con gửi cho Lan: mai bác về', 'Dạ đã gửi'), lessThan(0.5));
    expect(sayFidelity('', 'gì đó'), 1);
  });

  test('TranscriptBuffer gom delta và take xoá sạch', () {
    final b = TranscriptBuffer();
    expect(b.isEmpty, isTrue);
    b.add('nhắn ', 10);
    b.add('cho Lan', 20);
    expect(b.text, 'nhắn cho Lan');
    expect(b.lastChangeMs, 20);
    expect(b.take(), 'nhắn cho Lan');
    expect(b.isEmpty, isTrue);
    expect(b.lastChangeMs, -1);
  });
}
