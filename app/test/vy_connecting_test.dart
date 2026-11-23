import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/features/voice/core/vy_view.dart';
import 'package:vg_svthm/features/voice/presentation/vy_panel.dart';

Future<void> show(WidgetTester t, VyView v, {VoidCallback? onUseClassic, VoidCallback? onClose}) async {
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: VyPanel(
            view: v,
            onClose: onClose ?? () {},
            onPrimary: () {},
            onChip: (_) {},
            onCollapse: () {},
            onExpand: () {},
            onDismissIntro: () {},
            onUseClassic: onUseClassic,
          ),
        ),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('đang nối Live: khối kết nối lớn có thanh chuyển động, chưa có nút mic', (t) async {
    await show(t, const VyView(phase: VyPhase.opening, engine: VyEngine.live));
    expect(find.byKey(const Key('vy-connecting')), findsOneWidget);
    expect(find.text('Đang kết nối'), findsOneWidget);
    expect(find.byKey(const Key('vy-connecting-bar')), findsOneWidget);
    expect(find.byKey(const Key('vy-primary')), findsNothing);
    expect(find.byKey(const Key('vy-use-classic')), findsNothing, reason: 'chưa chờ lâu');
    await t.pumpWidget(const SizedBox()); // gỡ để dừng bộ đếm
  });

  testWidgets('chờ lâu: rồi hiện nút nói ngay bằng Vy thường; bấm được', (t) async {
    var classic = 0;
    await show(t, const VyView(phase: VyPhase.opening, engine: VyEngine.none), onUseClassic: () => classic++);
    await t.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('vy-use-classic')), findsNothing);
    for (var i = 0; i < 2; i++) {
      await t.pump(const Duration(seconds: 1));
    }
    expect(find.byKey(const Key('vy-use-classic')), findsOneWidget);
    await t.tap(find.byKey(const Key('vy-use-classic')));
    expect(classic, 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('có thể kết thúc ngay khi đang kết nối', (t) async {
    var closed = 0;
    await show(t, const VyView(phase: VyPhase.opening, engine: VyEngine.live), onClose: () => closed++);
    await t.tap(find.byKey(const Key('vy-end')));
    expect(closed, 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Vy thường đang chuẩn bị (chào xong mới mở mic): cũng hiện khối rõ ràng, không còn thanh nhỏ khó hiểu', (t) async {
    await show(t, const VyView(phase: VyPhase.opening, engine: VyEngine.classic));
    expect(find.byKey(const Key('vy-connecting')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
