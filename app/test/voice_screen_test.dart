import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/features/voice/domain/voice_models.dart';
import 'package:vg_svthm/features/voice/presentation/voice_controller.dart';
import 'package:vg_svthm/features/voice/presentation/voice_overlay.dart';

/// Controller giả: không đụng micro/loa, chỉ ghi lại thao tác từ giao diện.
class FakeVoice extends VoiceController {
  FakeVoice(this.initial);

  final VoiceState initial;
  final taps = <String>[];
  int toggles = 0;
  int closes = 0;

  @override
  VoiceState build() => initial;

  @override
  Future<void> toggle() async => toggles++;

  @override
  Future<void> close() async => closes++;

  @override
  Future<void> tapChip(String text) async => taps.add(text);
}

Future<FakeVoice> show(WidgetTester t, VoiceState s) async {
  final fake = FakeVoice(s);
  await t.pumpWidget(
    ProviderScope(
      overrides: [voiceControllerProvider.overrideWith(() => fake)],
      child: MaterialApp(theme: AppTheme.light, home: const VoiceScreen()),
    ),
  );
  await t.pump(const Duration(milliseconds: 300));
  return fake;
}

void main() {
  testWidgets('đang nghe: hiện trạng thái và nút gửi', (t) async {
    await show(t, const VoiceState(status: VoiceStatus.listening, panelOpen: true, level: 0.5));
    expect(find.text('Vy đang nghe…'), findsOneWidget);
    expect(find.text('Bấm để gửi'), findsOneWidget);
    expect(find.text('Kết thúc'), findsOneWidget);
  });

  testWidgets('đang nghĩ: hiện trạng thái và nút huỷ', (t) async {
    await show(t, const VoiceState(status: VoiceStatus.thinking, panelOpen: true, transcript: 'nhắn cho con'));
    expect(find.text('Vy đang nghĩ…'), findsOneWidget);
    expect(find.text('Huỷ'), findsOneWidget);
    expect(find.text('“nhắn cho con”'), findsOneWidget);
  });

  testWidgets('đang nói: hiện câu Vy nói và gợi ý bấm được', (t) async {
    final fake = await show(
      t,
      const VoiceState(
        status: VoiceStatus.speaking,
        panelOpen: true,
        say: 'Bác muốn nhắn cho ai ạ?',
        chips: ['Minh', 'Hoa'],
      ),
    );
    expect(find.text('Vy đang nói'), findsOneWidget);
    expect(find.text('Bác muốn nhắn cho ai ạ?'), findsOneWidget);
    await t.tap(find.text('Hoa'));
    expect(fake.taps, ['Hoa']);
  });

  testWidgets('xác nhận có/không: nút lớn Gửi, Sửa, Hủy', (t) async {
    final fake = await show(
      t,
      const VoiceState(
        status: VoiceStatus.idle,
        panelOpen: true,
        say: 'Gửi cho Minh: tối nay mẹ không ăn cơm nhà, đúng không ạ?',
        chips: ['Gửi', 'Sửa', 'Hủy'],
        dialog: VoiceDialog(expects: VoiceExpect.yesNo),
      ),
    );
    expect(find.widgetWithText(FilledButton, 'Gửi'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Sửa'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Hủy'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Gửi'));
    expect(fake.taps, ['Gửi']);
  });

  testWidgets('nút chính và nút kết thúc gọi đúng thao tác', (t) async {
    final fake = await show(t, const VoiceState(status: VoiceStatus.idle, panelOpen: true));
    expect(find.text('Bấm nút bên dưới để nói'), findsOneWidget);
    await t.tap(find.byKey(const Key('vy-primary')));
    await t.tap(find.byKey(const Key('vy-end')));
    expect(fake.toggles, 1);
    expect(fake.closes, 1);
  });

  testWidgets('lỗi hiện rõ trên màn Vy', (t) async {
    await show(t, const VoiceState(status: VoiceStatus.idle, panelOpen: true, error: 'Không có mạng'));
    expect(find.text('Không có mạng'), findsOneWidget);
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
