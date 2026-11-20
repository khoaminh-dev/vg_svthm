import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/features/voice/core/vy_greeting.dart';
import 'package:vg_svthm/features/voice/core/vy_view.dart';
import 'package:vg_svthm/features/voice/presentation/voice_overlay.dart';
import 'package:vg_svthm/features/voice/presentation/vy_panel.dart';

/// Ghi lại thao tác từ giao diện của panel.
class Taps {
  final chips = <String>[];
  int primary = 0;
  int close = 0;
  int collapse = 0;
  int expand = 0;
  int intro = 0;
  int call = 0;
}

Future<Taps> show(WidgetTester t, VyView v) async {
  final taps = Taps();
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: VyPanel(
            view: v,
            onClose: () => taps.close++,
            onPrimary: () => taps.primary++,
            onChip: taps.chips.add,
            onCollapse: () => taps.collapse++,
            onExpand: () => taps.expand++,
            onDismissIntro: () => taps.intro++,
            onCall115: () => taps.call++,
          ),
        ),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 300));
  return taps;
}

void main() {
  testWidgets('Vy thường đang nghe: trạng thái, nút gửi và nút kết thúc', (t) async {
    final taps = await show(
      t,
      const VyView(phase: VyPhase.listening, engine: VyEngine.classic, level: 0.5),
    );
    expect(find.text('Vy đang nghe…'), findsOneWidget);
    await t.tap(find.byKey(const Key('vy-primary')));
    await t.tap(find.byKey(const Key('vy-end')));
    expect(taps.primary, 1);
    expect(taps.close, 1);
  });

  testWidgets('đang nghĩ: nút Huỷ, câu người dùng hiện khi mở thẻ', (t) async {
    await show(
      t,
      const VyView(
        phase: VyPhase.thinking,
        engine: VyEngine.classic,
        userText: 'nhắn cho con',
        userExpanded: true,
      ),
    );
    expect(find.text('Vy đang nghĩ…'), findsOneWidget);
    expect(find.bySemanticsLabel('Huỷ'), findsOneWidget);
    expect(find.text('“nhắn cho con”'), findsOneWidget);
  });

  testWidgets('Vy Live: không có nút mic (micro luôn mở), chữ Vy nói hiện ở thanh nhỏ', (t) async {
    await show(
      t,
      const VyView(phase: VyPhase.ready, engine: VyEngine.live, vyText: 'Dạ, huyết áp của bác là 120 trên 80'),
    );
    expect(find.byKey(const Key('vy-primary')), findsNothing);
    expect(find.text('Dạ, huyết áp của bác là 120 trên 80'), findsOneWidget);
  });

  testWidgets('tắt "Hiện chữ khi Vy nói": thanh nhỏ không hiện chữ Vy', (t) async {
    await show(
      t,
      const VyView(
        phase: VyPhase.ready,
        engine: VyEngine.live,
        vyText: 'Dạ, huyết áp của bác là 120 trên 80',
        captions: false,
      ),
    );
    expect(find.text('Dạ, huyết áp của bác là 120 trên 80'), findsNothing);
  });

  testWidgets('tắt chữ nhưng đang xác nhận: vẫn phải hiện chữ để người dùng đọc', (t) async {
    await show(
      t,
      const VyView(
        phase: VyPhase.confirming,
        engine: VyEngine.live,
        vyText: 'Gửi cho Minh: mẹ khoẻ, đúng không ạ?',
        chips: ['Gửi', 'Sửa', 'Hủy'],
        captions: false,
      ),
    );
    expect(find.text('Gửi cho Minh: mẹ khoẻ, đúng không ạ?'), findsOneWidget);
  });

  testWidgets('có gợi ý bấm được: thẻ lớn, bấm gợi ý đi tới động cơ', (t) async {
    final taps = await show(
      t,
      const VyView(
        phase: VyPhase.speaking,
        engine: VyEngine.classic,
        vyText: 'Bác muốn nhắn cho ai ạ?',
        chips: ['Minh', 'Hoa'],
      ),
    );
    expect(find.text('Vy đang nói'), findsOneWidget);
    expect(find.text('Bác muốn nhắn cho ai ạ?'), findsOneWidget);
    await t.tap(find.text('Hoa'));
    expect(taps.chips, ['Hoa']);
  });

  testWidgets('xác nhận có/không: nút lớn Gửi, Sửa, Hủy', (t) async {
    final taps = await show(
      t,
      const VyView(
        phase: VyPhase.confirming,
        engine: VyEngine.live,
        vyText: 'Gửi cho Minh: tối nay mẹ không ăn cơm nhà, đúng không ạ?',
        chips: ['Gửi', 'Sửa', 'Hủy'],
      ),
    );
    expect(find.widgetWithText(FilledButton, 'Gửi'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Sửa'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Hủy'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Gửi'));
    expect(taps.chips, ['Gửi']);
  });

  testWidgets('khẩn cấp: thẻ đỏ có nút Gọi 115 do người dùng tự bấm', (t) async {
    final taps = await show(
      t,
      const VyView(
        phase: VyPhase.emergency,
        engine: VyEngine.live,
        vyText: 'Bác hãy bấm nút gọi người nhà hoặc gọi 115 ngay nhé.',
      ),
    );
    expect(find.text('Khẩn cấp'), findsOneWidget);
    await t.tap(find.byKey(const Key('vy-call-115')));
    expect(taps.call, 1);
  });

  testWidgets('lỗi hiện rõ trong thẻ', (t) async {
    await show(
      t,
      const VyView(phase: VyPhase.error, engine: VyEngine.classic, error: 'Không có mạng'),
    );
    expect(find.text('Vy gặp trục trặc'), findsOneWidget);
    expect(find.text('Không có mạng'), findsOneWidget);
  });

  testWidgets('thẻ giải thích lần đầu có nút Đã hiểu', (t) async {
    final taps = await show(
      t,
      const VyView(phase: VyPhase.ready, engine: VyEngine.live, showIntro: true),
    );
    expect(find.byKey(const Key('vy-intro')), findsOneWidget);
    await t.tap(find.byKey(const Key('vy-intro-ok')));
    expect(taps.intro, 1);
  });

  testWidgets('chạm vào quả cầu: thanh nhỏ mở rộng, thẻ lớn thu gọn', (t) async {
    final taps = await show(t, const VyView(phase: VyPhase.ready, engine: VyEngine.live));
    await t.tap(find.byType(GestureDetector).first);
    expect(taps.expand, 1);
  });

  group('trạng thái hiển thị', () {
    test('thẻ lớn tự mở khi có việc cần xem, người dùng thu gọn thì thôi', () {
      const base = VyView(phase: VyPhase.confirming, engine: VyEngine.live, chips: ['Gửi', 'Hủy']);
      expect(base.expanded, isTrue);
      expect(base.copyWith(collapsed: true).expanded, isFalse);
      const calm = VyView(phase: VyPhase.ready, engine: VyEngine.live);
      expect(calm.expanded, isFalse);
      expect(calm.copyWith(userExpanded: true).expanded, isTrue);
    });

    test('tailText giữ phần cuối của chữ dài', () {
      final long = List.generate(80, (i) => 'từ$i').join(' ');
      final t = tailText(long, max: 60);
      expect(t.startsWith('…'), isTrue);
      expect(t.endsWith('từ79'), isTrue);
      expect(tailText('ngắn'), 'ngắn');
    });
  });

  group('lời chào', () {
    test('mở lại gần đây chỉ "Dạ?"', () {
      expect(vyGreeting(now: DateTime(2026), honorific: 'bác', recent: true), 'Dạ?');
    });

    test('ba câu xoay vòng, đúng buổi và đúng cách xưng hô', () {
      final morning = DateTime(2026, 1, 1, 8);
      expect(vyGreeting(now: morning, honorific: 'cô', recent: false, variant: 0), 'Dạ, con nghe cô ạ');
      expect(vyGreeting(now: morning, honorific: 'cô', recent: false, variant: 1), 'Chào cô buổi sáng ạ');
      expect(vyGreeting(now: morning, honorific: 'cô', recent: false, variant: 2), 'Dạ, cô cần gì ạ');
      expect(vyGreeting(now: morning, honorific: 'cô', recent: false, variant: 3), 'Dạ, con nghe cô ạ');
      expect(vyGreeting(now: morning, honorific: '', recent: false), 'Dạ, con nghe bác ạ');
    });

    test('buổi trong ngày', () {
      expect(partOfDay(6), 'sáng');
      expect(partOfDay(12), 'trưa');
      expect(partOfDay(15), 'chiều');
      expect(partOfDay(20), 'tối');
    });

    test('câu hỏi khi im lặng viết hoa cách xưng hô', () {
      expect(vyStillThere('bác'), 'Bác còn cần con không ạ?');
    });
  });

  test('nút Vy nổi ẩn ở bốn tab chính và trong phòng chat, hiện ở màn phụ', () {
    for (final p in ['/', '/rooms', '/bp', '/profile', '/rooms/abc']) {
      expect(hidesVyButton(p), isTrue, reason: p);
    }
    for (final p in ['/ocr', '/ocr/edit', '/ocr/detail']) {
      expect(hidesVyButton(p), isFalse, reason: p);
    }
    expect(dockBottomFor('/ocr'), 24);
  });
}
