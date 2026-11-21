import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/features/voice/core/vy_card.dart';
import 'package:vg_svthm/features/voice/core/vy_core.dart';
import 'package:vg_svthm/features/voice/core/vy_settings.dart';
import 'package:vg_svthm/features/voice/core/vy_view.dart';
import 'package:vg_svthm/features/voice/live/live_lab_controller.dart';
import 'package:vg_svthm/features/voice/presentation/vy_cards.dart';
import 'package:vg_svthm/features/voice/presentation/voice_controller.dart';

import 'vy_core_test.dart' show FakeLive, FakeSay, FakeVoiceCtl;

class Rig {
  Rig({Map<String, Object> prefs = const {'vy_intro_seen': true, 'vy_sounds': false}}) {
    SharedPreferences.setMockInitialValues(prefs);
    c = ProviderContainer(overrides: [
      voiceControllerProvider.overrideWith(() => voice),
      liveLabProvider.overrideWith(() => live),
      vyVoiceProvider.overrideWithValue(say),
    ]);
    c.listen(vyCoreProvider, (_, _) {});
    c.read(vySettingsProvider);
  }

  late final ProviderContainer c;
  final voice = FakeVoiceCtl();
  final live = FakeLive();
  final say = FakeSay();

  VyCore get core => c.read(vyCoreProvider.notifier);
  VyView get view => c.read(vyCoreProvider);
}

void tick(FakeAsync a, [int ms = 100]) {
  a.flushMicrotasks();
  a.elapse(Duration(milliseconds: ms));
  a.flushMicrotasks();
}

NoticeCard card({List<VyCardAction> actions = const []}) =>
    NoticeCard(title: 'Đến giờ uống thuốc', body: '20:30 · Túi Tối', actions: actions);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('remind: mở panel bằng Vy thường, giọng máy nói câu nhắc, KHÔNG Live, KHÔNG mở mic, có thẻ', () {
    fakeAsync((a) {
      final r = Rig();
      tick(a);
      final ok = <bool>[];
      unawaited(r.core.remind(speech: 'Đến giờ uống thuốc rồi bác ơi.', card: card(), kind: 'dose').then(ok.add));
      tick(a);
      expect(ok, [true]);
      expect(r.view.isOpen, isTrue);
      expect(r.view.engine, VyEngine.classic);
      expect(r.view.phase, VyPhase.ready);
      expect(r.view.card, isA<NoticeCard>());
      expect(r.view.expanded, isTrue);
      expect(r.view.showIntro, isFalse); // nhắc không kèm thẻ giải thích lần đầu
      expect(r.say.said, ['Đến giờ uống thuốc rồi bác ơi.']);
      expect(r.live.starts, 0);
      expect(r.voice.toggles, 0);
      expect(r.voice.prepares, 0);
    });
  });

  test('remind khi Vy đang mở thì bỏ qua (không chen ngang)', () {
    fakeAsync((a) {
      final r = Rig();
      tick(a);
      unawaited(r.core.open());
      tick(a, 200);
      final ok = <bool>[];
      unawaited(r.core.remind(speech: 'x', card: card()).then(ok.add));
      tick(a);
      expect(ok, [false]);
      expect(r.view.card, isNull);
    });
  });

  test('bấm nút trên thẻ nhắc: làm việc đó rồi ĐÓNG Vy (không treo panel)', () {
    fakeAsync((a) {
      final r = Rig();
      tick(a);
      var done = 0;
      unawaited(r.core.remind(speech: 'x', card: card(actions: [VyCardAction(label: 'Đã uống', primary: true, run: () => done++)])));
      tick(a);
      r.core.runCardAction(r.view.card!.actions.single);
      tick(a);
      expect(done, 1);
      expect(r.view.isOpen, isFalse);
      expect(r.voice.toggles, 0);
    });
  });

  test('nút keepOpen ("Nghe"): giữ Vy mở, chuyển sang Vy thường thật (không mở mic) và gửi câu đi', () {
    fakeAsync((a) {
      final r = Rig();
      tick(a);
      late VyCore core;
      core = r.core;
      unawaited(core.remind(
        speech: 'x',
        card: card(actions: [VyCardAction(label: 'Nghe', keepOpen: true, run: () => unawaited(core.sendText('đọc tin nhắn')))]),
      ));
      tick(a);
      core.runCardAction(r.view.card!.actions.single);
      tick(a, 50);
      expect(r.view.isOpen, isTrue);
      expect(r.voice.prepares, 1);
      expect(r.voice.toggles, 0); // vẫn chưa mở mic
      expect(r.voice.taps, ['đọc tin nhắn']);
      expect(r.live.starts, 0);
    });
  });

  test('bấm mic khi đang nhắc: mới chuẩn bị phiên và mở mic', () {
    fakeAsync((a) {
      final r = Rig();
      tick(a);
      unawaited(r.core.remind(speech: 'x', card: card()));
      tick(a);
      unawaited(r.core.primary());
      tick(a, 50);
      expect(r.voice.prepares, 1);
      expect(r.voice.toggles, 1);
      expect(r.view.isOpen, isTrue);
    });
  });

  test('không ai trả lời: tự đóng êm sau 45 giây, không hỏi "còn cần con không"', () {
    fakeAsync((a) {
      final r = Rig();
      tick(a);
      unawaited(r.core.remind(speech: 'x', card: card()));
      tick(a);
      a.elapse(const Duration(seconds: 44));
      a.flushMicrotasks();
      expect(r.view.isOpen, isTrue);
      expect(r.view.idlePrompt, isFalse);
      a.elapse(const Duration(seconds: 2));
      a.flushMicrotasks();
      expect(r.view.isOpen, isFalse);
      expect(r.say.said, ['x']); // không có câu hỏi thêm
    });
  });

  test('người dùng chạm nút Vy khi đang nhắc: nâng lên phiên đầy đủ (Live nếu được)', () {
    fakeAsync((a) {
      final r = Rig();
      tick(a);
      unawaited(r.core.remind(speech: 'x', card: card()));
      tick(a);
      unawaited(r.core.open());
      tick(a, 300);
      expect(r.view.isOpen, isTrue);
      expect(r.view.engine, VyEngine.live);
      expect(r.live.starts, 1);
      expect(r.view.card, isNull); // thẻ nhắc đã được dọn
    });
  });

  test('đóng bằng X giữa lúc nhắc: gỡ thẻ, và mở Vy lần sau KHÔNG ở chế độ nhắc', () {
    fakeAsync((a) {
      final r = Rig();
      tick(a);
      unawaited(r.core.remind(speech: 'x', card: card()));
      tick(a);
      unawaited(r.core.close());
      tick(a);
      expect(r.view.isOpen, isFalse);
      expect(r.c.read(vyCardProvider), isNull);
      unawaited(r.core.open());
      tick(a, 300);
      expect(r.view.engine, VyEngine.live);
    });
  });

  test('Back khi đang nhắc: thu thẻ lớn về thanh nhỏ, lần nữa mới đóng', () {
    fakeAsync((a) {
      final r = Rig();
      tick(a);
      unawaited(r.core.remind(speech: 'x', card: card()));
      tick(a);
      expect(r.view.expanded, isTrue);
      expect(r.core.back(), isTrue);
      tick(a, 10);
      expect(r.view.isOpen, isTrue);
      expect(r.view.expanded, isFalse);
      expect(r.core.back(), isTrue);
      tick(a, 10);
      expect(r.view.isOpen, isFalse);
    });
  });

  testWidgets('thẻ nhắc: tiêu đề, nội dung và nút trả lời hiện đúng', (t) async {
    var done = 0;
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: VyCardView(
            card: card(actions: [
              VyCardAction(label: 'Đã uống', primary: true, run: () => done++),
              VyCardAction(label: 'Nhắc lại sau 15 phút', run: () {}),
            ]),
            onAction: (x) => x.run(),
          ),
        ),
      ),
    );
    expect(find.text('Đến giờ uống thuốc'), findsOneWidget);
    expect(find.text('20:30 · Túi Tối'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Đã uống'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Nhắc lại sau 15 phút'), findsOneWidget);
    await t.tap(find.text('Đã uống'));
    expect(done, 1);
  });

  test('cài đặt "Vy tự nhắc": bật sẵn, tắt từng loại được và nhớ lại', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final s0 = await c.read(vySettingsProvider.future);
    expect([s0.remindDose, s0.remindBp, s0.remindMessages], [true, true, true]);
    await c.read(vySettingsProvider.notifier).setRemind(bp: false);
    final s1 = c.read(vySettingsProvider).value!;
    expect([s1.remindDose, s1.remindBp, s1.remindMessages], [true, false, true]);
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    final s2 = await c2.read(vySettingsProvider.future);
    expect([s2.remindDose, s2.remindBp, s2.remindMessages], [true, false, true]);
  });
}
