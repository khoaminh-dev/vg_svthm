import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/features/auth/domain/auth_user.dart';
import 'package:vg_svthm/features/auth/presentation/providers/auth_providers.dart';
import 'package:vg_svthm/features/bp/presentation/providers/bp_providers.dart';
import 'package:vg_svthm/features/health/presentation/providers/health_providers.dart';
import 'package:vg_svthm/features/home/presentation/elder_home_screen.dart';
import 'package:vg_svthm/features/meds/presentation/meds_providers.dart';
import 'package:vg_svthm/features/safety/presentation/sos_widgets.dart';

import 'family_test.dart' show FakeBp;
import 'health_test.dart' show FakeHealthRepository;
import 'meds_test.dart' show FakeMeds, dose;

Widget hostElder(FakeMeds meds) => ProviderScope(
  key: UniqueKey(),
  overrides: [
    currentUserProvider.overrideWithValue(const AuthUser(id: 'me', username: 'minh', fullName: 'Bác Hùng', role: AppRole.elder)),
    bpRepositoryProvider.overrideWithValue(FakeBp({})),
    healthRepositoryProvider.overrideWithValue(FakeHealthRepository()),
    medsRepositoryProvider.overrideWithValue(meds),
  ],
  child: MaterialApp(theme: AppTheme.light, home: const ElderHomeScreen()),
);

/// Quả cầu Vy chuyển động liên tục nên pumpAndSettle không bao giờ yên: bơm vài khung hình.
Future<void> pump(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 200));
  }
}

void bigScreen(WidgetTester t) {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.5;
  addTearDown(t.view.reset);
}

void main() {
  testWidgets('trang chủ người cao tuổi: thẻ Vy, 6 ô lớn, SOS, không thanh điều hướng', (t) async {
    bigScreen(t);
    await t.pumpWidget(hostElder(FakeMeds()));
    await pump(t);
    expect(find.byKey(const Key('elder-home')), findsOneWidget);
    expect(find.byKey(const Key('elder-vy')), findsOneWidget, reason: 'Vy luôn hiện ở đầu trang chủ');
    expect(find.text('Nói với Vy'), findsOneWidget);
    for (final tile in elderTiles) {
      expect(find.byKey(Key('elder-tile-${tile.key}')), findsOneWidget, reason: tile.label);
    }
    expect(find.text('Tin nhắn'), findsOneWidget);
    expect(find.text('Cộng đồng'), findsOneWidget);
    expect(find.text('Thư giãn'), findsOneWidget);
    expect(elderTiles.length, 6);
    expect(find.byKey(const Key('elder-avatar')), findsOneWidget, reason: 'Hồ sơ mở bằng avatar');
    expect(find.byType(SosHoldButton), findsOneWidget);
    expect(find.byKey(const Key('elder-dose-none')), findsOneWidget);
    expect(find.text('--/--'), findsOneWidget);
  });

  testWidgets('đến giờ uống thuốc: có nút "Đã uống" to và bấm là ghi nhận', (t) async {
    bigScreen(t);
    final n = DateTime.now();
    final meds = FakeMeds(doses: [dose('d1', 'Sáng', n.subtract(const Duration(minutes: 10)))]);
    await t.pumpWidget(hostElder(meds));
    await pump(t);
    expect(find.text('Đến giờ uống thuốc'), findsOneWidget);
    await t.tap(find.byKey(const Key('elder-dose-taken-d1')));
    await pump(t);
    expect(meds.calls, contains('taken:d1'));
  });

  testWidgets('chưa tới giờ: chỉ hiện thuốc kế tiếp, không có nút "Đã uống"', (t) async {
    bigScreen(t);
    final meds = FakeMeds(doses: [dose('d2', 'Tối', DateTime.now().add(const Duration(hours: 3)))]);
    await t.pumpWidget(hostElder(meds));
    await pump(t);
    expect(find.text('Thuốc kế tiếp'), findsOneWidget);
    expect(find.byKey(const Key('elder-dose-taken-d2')), findsNothing);
  });
}
