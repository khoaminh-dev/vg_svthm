import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/features/auth/domain/auth_user.dart';
import 'package:vg_svthm/features/auth/presentation/providers/auth_providers.dart';
import 'package:vg_svthm/features/bp/domain/bp_models.dart';
import 'package:vg_svthm/features/bp/presentation/providers/bp_providers.dart';
import 'package:vg_svthm/features/bp/presentation/screens/bp_screen.dart';
import 'package:vg_svthm/features/health/presentation/providers/health_providers.dart';
import 'package:vg_svthm/features/meds/presentation/meds_providers.dart';

import 'family_test.dart' show FakeBp;
import 'health_test.dart' show FakeHealthRepository;
import 'meds_test.dart' show FakeMeds;

final _now = DateTime(2026, 11, 23, 9);
BpReading _r(int s, int d, int daysAgo, {bool? ok}) => BpReading(
  id: '$s-$d-$daysAgo',
  systolic: s,
  diastolic: d,
  measuredAt: _now.subtract(Duration(days: daysAgo)),
  protocolOk: ok,
);

void main() {
  group('BpReading.displayLabel', () {
    test('cao mà biết chưa đủ chuẩn: chỉ gọi "Số đo cao", không gắn nhãn chẩn đoán', () {
      expect(_r(150, 95, 0, ok: false).displayLabel, 'Số đo cao');
      expect(_r(125, 75, 0, ok: false).displayLabel, 'Số đo cao');
    });
    test('đủ chuẩn, số cũ không rõ, bình thường, khẩn cấp: giữ nhãn gốc', () {
      expect(_r(150, 95, 0, ok: true).displayLabel, BpCategory.stage2.label);
      expect(_r(150, 95, 0).displayLabel, BpCategory.stage2.label);
      expect(_r(110, 70, 0, ok: false).displayLabel, BpCategory.normal.label);
      expect(_r(190, 110, 0, ok: false).displayLabel, BpCategory.crisis.label);
    });
  });

  group('BpWeek', () {
    test('không có số đo trong 7 ngày: null', () {
      expect(BpWeek.of([], _now), isNull);
      expect(BpWeek.of([_r(120, 80, 9)], _now), isNull);
    });
    test('bỏ số chưa đủ chuẩn, tính trung bình số còn lại, đếm ngày khác nhau', () {
      final w = BpWeek.of([
        _r(150, 95, 0, ok: false), // bỏ
        _r(120, 80, 0, ok: true),
        _r(130, 84, 1),
        _r(140, 90, 1, ok: true),
        _r(110, 70, 8, ok: true), // quá 7 ngày
      ], _now)!;
      expect(w.readings, 3);
      expect(w.days, 2);
      expect((w.avgSys, w.avgDia), (130, 85));
      expect(w.enough, isFalse);
      expect(w.daysMissing, 1);
    });
    test('đủ 3 ngày thì đánh giá theo phân loại AHA', () {
      final w = BpWeek.of([_r(134, 84, 0), _r(132, 82, 1), _r(136, 86, 2)], _now)!;
      expect(w.enough, isTrue);
      expect(w.category, BpCategory.stage1);
    });
    test('toàn số chưa đủ chuẩn: không có trung bình', () {
      expect(BpWeek.of([_r(150, 95, 0, ok: false)], _now), isNull);
    });
  });

  Widget host(List<BpReading> list) => ProviderScope(
    key: UniqueKey(),
    overrides: [
      currentUserProvider.overrideWithValue(const AuthUser(id: 'me', username: 'minh', role: AppRole.family)),
      bpRepositoryProvider.overrideWithValue(FakeBp({})),
      bpReadingsProvider.overrideWith((ref) async => list),
      healthRepositoryProvider.overrideWithValue(FakeHealthRepository()),
      medsRepositoryProvider.overrideWithValue(FakeMeds()),
    ],
    child: MaterialApp(theme: AppTheme.light, home: const BpScreen()),
  );

  testWidgets('màn Theo dõi: thẻ 7 ngày nói cần đo thêm khi chưa đủ 3 ngày; số chưa chuẩn không gắn nhãn chẩn đoán', (t) async {
    t.view.physicalSize = const Size(1080, 3200);
    t.view.devicePixelRatio = 2.5;
    addTearDown(t.view.reset);
    final now = DateTime.now();
    final list = [
      BpReading(id: 'a', systolic: 150, diastolic: 95, measuredAt: now, protocolOk: false),
      BpReading(id: 'b', systolic: 120, diastolic: 78, measuredAt: now.subtract(const Duration(hours: 5)), protocolOk: true),
    ];
    await t.pumpWidget(host(list));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('bp-week')), findsOneWidget);
    expect(find.byKey(const Key('bp-week-need')), findsOneWidget);
    expect(find.textContaining('Cần đo thêm 2 ngày'), findsOneWidget);
    expect(find.text('Trung bình 120/78 mmHg'), findsOneWidget);
    expect(find.text('Số đo cao'), findsWidgets);
    expect(find.textContaining('chưa đủ chuẩn'), findsWidgets);
    expect(find.textContaining('Tăng huyết áp độ 2'), findsNothing);
  });
}
