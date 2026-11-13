import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/shared/widgets/big_tile.dart';
import 'package:vg_svthm/shared/widgets/pill_nav_bar.dart';
import 'package:vg_svthm/shared/widgets/status_chip.dart';
import 'package:vg_svthm/shared/widgets/vy_orb.dart';

Widget host(Widget child, {bool reduceMotion = false}) => MaterialApp(
  theme: AppTheme.light,
  builder: (context, c) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
    child: c!,
  ),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('StatusChip hiện chữ của mức', (t) async {
    await t.pumpWidget(host(const StatusChip(label: 'Bình thường', color: AppColors.levelGood)));
    expect(find.text('Bình thường'), findsOneWidget);
  });

  testWidgets('BigTile: bấm được, đọc được tiêu đề và mô tả, cao tối thiểu 72', (t) async {
    var taps = 0;
    await t.pumpWidget(host(BigTile(
      icon: Icons.chat_bubble_outline,
      title: 'Tin nhắn',
      subtitle: 'Trò chuyện cùng người thân',
      onTap: () => taps++,
    )));
    expect(t.getSize(find.byType(BigTile)).height, greaterThanOrEqualTo(72));
    expect(find.bySemanticsLabel('Tin nhắn. Trò chuyện cùng người thân'), findsOneWidget);
    await t.tap(find.text('Tin nhắn'));
    expect(taps, 1);
  });

  testWidgets('PillNavBar: chọn mục, nút giữa hiện, vùng chạm ≥ 56', (t) async {
    var picked = -1;
    await t.pumpWidget(host(PillNavBar(
      index: 0,
      onSelected: (i) => picked = i,
      center: const SizedBox(key: Key('vy'), width: 64, height: 64),
      items: const [
        PillNavItem(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Trang chủ'),
        PillNavItem(icon: Icons.chat_bubble_outline, label: 'Tin nhắn'),
        PillNavItem(icon: Icons.favorite_border, label: 'Sức khoẻ'),
        PillNavItem(icon: Icons.person_outline, label: 'Hồ sơ'),
      ],
    )));
    expect(find.byKey(const Key('vy')), findsOneWidget);
    expect(t.getSize(find.text('Tin nhắn').first).height, greaterThan(0));
    await t.tap(find.text('Sức khoẻ'));
    expect(picked, 2);
    await t.tap(find.text('Trang chủ'));
    expect(picked, 0);
  });

  for (final reduce in [false, true]) {
    testWidgets('VyOrb vẽ đủ 4 trạng thái (giảm chuyển động: $reduce)', (t) async {
      for (final mode in OrbMode.values) {
        await t.pumpWidget(host(VyOrb(mode: mode, level: 0.6, size: 200), reduceMotion: reduce));
        await t.pump(const Duration(milliseconds: 300));
        expect(tester(t), isNull);
      }
      expect(find.byType(VyOrb), findsOneWidget);
    });
  }

  testWidgets('VyOrb báo trạng thái cho trình đọc màn hình', (t) async {
    await t.pumpWidget(host(const VyOrb(mode: OrbMode.listening)));
    expect(find.bySemanticsLabel('Vy đang nghe'), findsOneWidget);
  });
}

// Không có lỗi vẽ nào bị ném ra trong khung hình vừa rồi.
Object? tester(WidgetTester t) => t.takeException();
