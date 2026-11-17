import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/features/auth/domain/auth_user.dart';
import 'package:vg_svthm/features/auth/presentation/providers/auth_providers.dart';
import 'package:vg_svthm/features/bp/presentation/providers/bp_providers.dart';
import 'package:vg_svthm/features/chat/presentation/providers/chat_providers.dart';
import 'package:vg_svthm/features/chat/presentation/screens/room_list_screen.dart';
import 'package:vg_svthm/features/family/presentation/family_providers.dart';
import 'package:vg_svthm/shared/widgets/elder_text_scale.dart';
import 'package:vg_svthm/features/bp/presentation/screens/bp_screen.dart';
import 'package:vg_svthm/features/health/presentation/providers/health_providers.dart';
import 'package:vg_svthm/features/meds/presentation/meds_providers.dart';

import 'family_test.dart' show FakeBp, FakeFamily, link;
import 'health_test.dart' show FakeHealthRepository;
import 'meds_test.dart' show FakeMeds;

Widget host(AppRole role) => ProviderScope(
  key: UniqueKey(),
  overrides: [
    currentUserProvider.overrideWithValue(AuthUser(id: 'me', username: 'minh', role: role)),
    bpRepositoryProvider.overrideWithValue(FakeBp({})),
    healthRepositoryProvider.overrideWithValue(FakeHealthRepository()),
    medsRepositoryProvider.overrideWithValue(FakeMeds()),
  ],
  child: MaterialApp(theme: AppTheme.light, home: const BpScreen()),
);

void main() {
  testWidgets('màn Huyết áp của người cao tuổi: không có thanh tab, có nút "Đo huyết áp bây giờ" to', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.5;
    addTearDown(t.view.reset);
    await t.pumpWidget(host(AppRole.elder));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('elder-bp-view')), findsOneWidget);
    expect(find.byKey(const Key('health-tabs')), findsNothing);
    expect(find.byKey(const Key('elder-bp-measure')), findsOneWidget);
    expect(t.getSize(find.byKey(const Key('elder-bp-measure'))).height, greaterThanOrEqualTo(72));
    expect(find.byKey(const Key('elder-bp-empty')), findsOneWidget);
  });

  testWidgets('người thân vẫn có thanh tab Huyết áp / Đánh giá / Thuốc', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.5;
    addTearDown(t.view.reset);
    await t.pumpWidget(host(AppRole.family));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('health-tabs')), findsOneWidget);
    expect(find.byKey(const Key('elder-bp-view')), findsNothing);
  });

  test('elderScaleFor: tối thiểu 1,2, theo cỡ hệ thống nếu lớn hơn, tối đa 1,6', () {
    expect(elderScaleFor(1.0), 1.2);
    expect(elderScaleFor(1.4), 1.4);
    expect(elderScaleFor(2.0), 1.6);
  });
}
