import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/features/voice/core/vy_card.dart';
import 'package:vg_svthm/features/voice/data/voice_actions.dart';
import 'package:vg_svthm/features/voice/domain/voice_models.dart';
import 'package:vg_svthm/features/voice/presentation/vy_cards.dart';

Widget host(SendCard c) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: SingleChildScrollView(child: VyCardView(card: c, onAction: (a) => a.run()))),
);

void main() {
  testWidgets('thẻ gửi tin: tên to, nội dung, đếm ngược rồi tự gửi đúng một lần', (t) async {
    var sent = 0;
    await t.pumpWidget(host(SendCard(name: 'Hải', text: 'Hải ăn cơm chưa?', seconds: 3, onSend: () => sent++)));
    expect(find.text('Hải'), findsOneWidget);
    expect(find.text('Hải ăn cơm chưa?'), findsOneWidget);
    expect(find.byKey(const Key('vy-send-count')), findsOneWidget);
    expect(find.byKey(const Key('vy-send-fuzzy')), findsNothing);
    final nameSize = t.widget<Text>(find.byKey(const Key('vy-send-name'))).style!.fontSize!;
    final textSize = t.widget<Text>(find.byKey(const Key('vy-send-text'))).style!.fontSize!;
    expect(nameSize, greaterThan(textSize), reason: 'tên là thứ to nhất để người dùng bắt lỗi');
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    expect(sent, 0);
    await t.pump(const Duration(seconds: 1));
    expect(sent, 1);
    await t.pump(const Duration(seconds: 5));
    expect(sent, 1, reason: 'chỉ gửi một lần');
  });

  testWidgets('tên khớp gần giống: có dòng nhắc kiểm tra tên', (t) async {
    await t.pumpWidget(host(SendCard(name: 'Hải', text: 'Chào', seconds: 6, fuzzy: true, onSend: () {})));
    expect(find.byKey(const Key('vy-send-fuzzy')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('gỡ thẻ trước khi hết giờ (huỷ/đóng Vy) thì KHÔNG gửi', (t) async {
    var sent = 0;
    await t.pumpWidget(host(SendCard(name: 'Hải', text: 'Chào', seconds: 3, onSend: () => sent++)));
    await t.pump(const Duration(seconds: 1));
    await t.pumpWidget(const SizedBox()); // thẻ bị gỡ
    await t.pump(const Duration(seconds: 5));
    expect(sent, 0);
  });

  test('chỉ tự gửi khi đã khớp người trong danh bạ và có nội dung', () {
    VoiceTask task(Map<String, String> s) => VoiceTask(intent: 'send_message', slots: s);
    expect(VoiceActions.canAutoSend(task({'room_id': 'r1', 'content': 'Chào'})), true);
    expect(VoiceActions.canAutoSend(task({'room_id': '', 'content': 'Chào'})), false);
    expect(VoiceActions.canAutoSend(task({'room_id': 'r1', 'content': '  '})), false);
    expect(VoiceActions.canAutoSend(null), false);
    expect(VoiceActions.canAutoSend(VoiceTask(intent: 'open_chat', slots: {'room_id': 'r1', 'content': 'x'})), false);
  });
}
