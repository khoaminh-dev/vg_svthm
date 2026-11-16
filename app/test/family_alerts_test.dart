import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/features/auth/domain/auth_user.dart';
import 'package:vg_svthm/features/auth/presentation/providers/auth_providers.dart';
import 'package:vg_svthm/features/bp/domain/bp_models.dart';
import 'package:vg_svthm/features/bp/presentation/providers/bp_providers.dart';
import 'package:vg_svthm/features/family/domain/alerts_feed.dart';
import 'package:vg_svthm/features/family/domain/family_models.dart';
import 'package:vg_svthm/features/family/presentation/alerts_screen.dart';
import 'package:vg_svthm/features/family/presentation/family_providers.dart';
import 'package:vg_svthm/features/health/presentation/providers/health_providers.dart';
import 'package:vg_svthm/features/meds/presentation/meds_providers.dart';
import 'package:vg_svthm/features/safety/domain/safety_models.dart';
import 'package:vg_svthm/features/safety/presentation/safety_providers.dart';

import 'family_test.dart' show FakeBp, FakeFamily, link;
import 'health_test.dart' show FakeHealthRepository;
import 'meds_test.dart' show FakeMeds, dose;
import 'safety_test.dart' show FakeSafety;

BpReading reading(int s, int d, DateTime at) => BpReading(systolic: s, diastolic: d, measuredAt: at);

void main() {
  final now = DateTime(2026, 11, 16, 15, 0);

  group('buildAlerts', () {
    test('huyết áp: từ 180/120 là đỏ, từ 160/100 là cam, bình thường thì bỏ; quá 7 ngày thì bỏ', () {
      final items = buildAlerts(
        links: [link('l1')],
        bp: {
          'p1': [
            reading(185, 122, now.subtract(const Duration(hours: 1))),
            reading(165, 95, now.subtract(const Duration(hours: 5))),
            reading(120, 80, now.subtract(const Duration(hours: 6))),
            reading(190, 125, now.subtract(const Duration(days: 9))),
          ],
        },
        doses: const {},
        sos: const [],
        now: now,
      );
      expect(items.map((a) => a.kind), [AlertKind.bpCrisis, AlertKind.bpHigh]);
      expect(items.first.level, AlertLevel.red);
      expect(items.first.detail, contains('185/122'));
      expect(items.last.level, AlertLevel.orange);
    });

    test('cữ thuốc bị bỏ lỡ là cảnh báo; đã uống, bỏ qua, chưa tới giờ thì không', () {
      final items = buildAlerts(
        links: [link('l1')],
        bp: const {},
        doses: {
          'p1': [
            dose('a', 'Sáng', DateTime(2026, 11, 16, 7), status: 'missed'),
            dose('b', 'Trưa', DateTime(2026, 11, 16, 11), status: 'taken'),
            dose('c', 'Chiều', DateTime(2026, 11, 16, 12), status: 'skipped'),
            dose('d', 'Tối', DateTime(2026, 11, 16, 20)),
          ],
        },
        sos: const [],
        now: now,
      );
      expect(items.length, 1);
      expect(items.single.kind, AlertKind.doseMissed);
      expect(items.single.title, contains('túi Sáng'));
    });

    test('SOS: chưa ai nhận là đỏ, đã nhận là cam kèm tên người nhận, đã huỷ là xám', () {
      final links = [link('l1'), link('l2', other: 'c2', name: 'Anh Nam')];
      SosEvent e(String id, {bool handled = false, bool cancelled = false, String? by, int minutes = 10}) => SosEvent(
        id: id,
        ownerId: 'p1',
        createdAt: now.subtract(Duration(minutes: minutes)),
        handled: handled,
        cancelled: cancelled,
        handledBy: by,
        handledAt: handled ? now.subtract(Duration(minutes: minutes - 2)) : null,
      );
      final items = buildAlerts(
        links: links,
        bp: const {},
        doses: const {},
        sos: [e('s1'), e('s2', handled: true, by: 'c2', minutes: 60), e('s3', handled: true, cancelled: true, minutes: 120)],
        now: now,
      );
      expect(items.map((a) => a.level), [AlertLevel.red, AlertLevel.orange, AlertLevel.info]);
      expect(items[1].detail, contains('Anh Nam đã nhận'));
      expect(items.first.sosId, 's1');
      // Chính mình nhận thì hiện 'Bạn đã nhận'.
      final mine = buildAlerts(links: links, bp: const {}, doses: const {}, sos: [e('s2', handled: true, by: 'me', minutes: 60)], now: now, myId: 'me');
      expect(mine.single.detail, startsWith('Bạn đã nhận'));
    });

    test('tôn trọng quyền: thiếu health, meds_view, alerts thì không thấy huyết áp, thuốc, SOS', () {
      final none = link('l1', perms: {FamilyPerm.health: false, FamilyPerm.medsView: false, FamilyPerm.alerts: false});
      final items = buildAlerts(
        links: [none],
        bp: {'p1': [reading(190, 125, now)]},
        doses: {'p1': [dose('a', 'Sáng', DateTime(2026, 11, 16, 7), status: 'missed')]},
        sos: [SosEvent(id: 's', ownerId: 'p1', createdAt: now, handled: false)],
        now: now,
      );
      expect(items, isEmpty);
    });

    test('dayLabel', () {
      expect(dayLabel(now, now), 'Hôm nay');
      expect(dayLabel(now.subtract(const Duration(days: 1)), now), 'Hôm qua');
      expect(dayLabel(DateTime(2026, 11, 12), now), '12/11');
    });
  });

  Widget host(FakeFamily fam, {FakeBp? bp, FakeMeds? meds, FakeSafety? safety}) => ProviderScope(
    key: UniqueKey(),
    overrides: [
      currentUserProvider.overrideWithValue(const AuthUser(id: 'me', username: 'minh', role: AppRole.family)),
      familyRepositoryProvider.overrideWithValue(fam),
      bpRepositoryProvider.overrideWithValue(bp ?? FakeBp({})),
      healthRepositoryProvider.overrideWithValue(FakeHealthRepository()),
      medsRepositoryProvider.overrideWithValue(meds ?? FakeMeds()),
      safetyRepositoryProvider.overrideWithValue(safety ?? FakeSafety()),
    ],
    child: MaterialApp(theme: AppTheme.light, home: const AlertsScreen()),
  );

  void big(WidgetTester t) {
    t.view.physicalSize = const Size(900, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  testWidgets('tab Cảnh báo: chưa theo dõi ai thì mời nhập mã', (t) async {
    big(t);
    await t.pumpWidget(host(FakeFamily()));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('alerts-nobody')), findsOneWidget);
    expect(find.byKey(const Key('alerts-join')), findsOneWidget);
  });

  testWidgets('tab Cảnh báo: theo dõi nhưng chưa có gì thì báo "Mọi thứ đều ổn"', (t) async {
    big(t);
    await t.pumpWidget(host(FakeFamily(links: [link('l1')])));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('alerts-empty')), findsOneWidget);
    expect(find.text('Mọi thứ đều ổn'), findsOneWidget);
  });

  testWidgets('tab Cảnh báo: có huyết áp rất cao, thuốc bỏ lỡ và SOS thì hiện đủ, nhóm theo ngày', (t) async {
    big(t);
    final n = DateTime.now();
    final fixedBp = FakeBp({'p1': [reading(186, 123, n.subtract(const Duration(minutes: 30)))]});
    final meds = FakeMeds(doses: [dose('m1', 'Sáng', DateTime(n.year, n.month, n.day, 0, 1), status: 'missed')]);
    final safety = FakeSafety(event: SosEvent(id: 's1', ownerId: 'p1', createdAt: n.subtract(const Duration(minutes: 5)), handled: false));
    await t.pumpWidget(host(FakeFamily(links: [link('l1')]), bp: fixedBp, meds: meds, safety: safety));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('alerts-list')), findsOneWidget);
    expect(find.text('Hôm nay'), findsOneWidget);
    expect(find.textContaining('đã bấm SOS'), findsOneWidget);
    expect(find.textContaining('rất cao'), findsOneWidget);
    expect(find.textContaining('chưa uống túi Sáng'), findsOneWidget);
    expect(find.textContaining('Chưa ai nhận'), findsOneWidget);
  });
}
