import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/features/auth/domain/auth_user.dart';
import 'package:vg_svthm/features/auth/presentation/providers/auth_providers.dart';
import 'package:vg_svthm/features/plan/data/plan_repository.dart';
import 'package:vg_svthm/features/plan/domain/plan_models.dart';
import 'package:vg_svthm/features/plan/presentation/plan_screen.dart';

class FakePlans implements PlanRepository {
  FakePlans(this.state);

  PlanOverview state;
  final calls = <String>[];

  @override
  Future<PlanOverview> overview() async => state;

  @override
  Future<PlanOrder> request(String planId) async {
    calls.add('request:$planId');
    final p = state.plans.firstWhere((x) => x.id == planId);
    final order = PlanOrder(
      code: 'VGABC123',
      planName: p.name,
      priceVnd: p.priceVnd,
      days: p.days,
      status: PlanStatus.pending,
    );
    state = PlanOverview(plans: state.plans, payNote: state.payNote, mine: order);
    return order;
  }

  @override
  Future<void> cancelPending() async {
    calls.add('cancel');
    state = PlanOverview(plans: state.plans, payNote: state.payNote);
  }
}

const _month = PlanOption(id: 'p1', name: 'Gói tháng', priceVnd: 99000, days: 30);

Widget host(FakePlans repo, {AppRole role = AppRole.family}) => ProviderScope(
  overrides: [
    currentUserProvider.overrideWithValue(AuthUser(id: 'me', username: 'minh', role: role)),
    planRepositoryProvider.overrideWithValue(repo),
  ],
  child: MaterialApp(theme: AppTheme.light, home: const PlanScreen()),
);

void main() {
  test('định dạng tiền và ngày', () {
    expect(formatVnd(99000), '99.000đ');
    expect(formatVnd(1250000), '1.250.000đ');
    expect(formatVnd(500), '500đ');
    expect(formatDay(DateTime(2026, 3, 5)), '05/03/2026');
  });

  test('đơn chỉ có hiệu lực khi đã xác nhận và chưa hết hạn', () {
    final now = DateTime(2026, 11, 21);
    PlanOrder o(PlanStatus s, DateTime? exp) =>
        PlanOrder(code: 'X', planName: 'A', priceVnd: 1, days: 1, status: s, expiresAt: exp);
    expect(o(PlanStatus.active, now.add(const Duration(days: 1))).isLiveAt(now), true);
    expect(o(PlanStatus.active, now.subtract(const Duration(days: 1))).isLiveAt(now), false);
    expect(o(PlanStatus.pending, now.add(const Duration(days: 1))).isLiveAt(now), false);
    expect(o(PlanStatus.active, null).isLiveAt(now), false);
  });

  test('đọc toàn cảnh từ JSON của máy chủ', () {
    final o = PlanOverview.fromJson({
      'plans': [
        {'id': 'p1', 'name': 'Gói tháng', 'price_vnd': 99000, 'days': 30, 'note': ''},
      ],
      'pay_note': 'Chuyển khoản',
      'mine': {
        'order_code': 'VGAAA111',
        'plan_name': 'Gói tháng',
        'price_vnd': 99000,
        'days': 30,
        'status': 'pending',
        'created_at': '2026-11-21T01:00:00Z',
        'expires_at': null,
      },
      'covered_by': null,
      'live': false,
    });
    expect(o.plans.single.priceVnd, 99000);
    expect(o.mine!.isPending, true);
    expect(o.live, false);
  });

  testWidgets('chưa có gói nào đang bán thì nói rõ', (t) async {
    await t.pumpWidget(host(FakePlans(const PlanOverview())));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('plan-none')), findsOneWidget);
    expect(find.text('Chưa bật Vy Live'), findsOneWidget);
  });

  testWidgets('đặt gói: hỏi lại, rồi hiện mã đơn và nút huỷ; huỷ thì quay lại danh sách', (t) async {
    final repo = FakePlans(const PlanOverview(plans: [_month], payNote: 'Ghi mã đơn khi chuyển khoản'));
    await t.pumpWidget(host(repo));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('plan-p1')));
    await t.pumpAndSettle();
    expect(find.text('Đặt Gói tháng?'), findsOneWidget);
    await t.tap(find.byKey(const Key('plan-cancel')));
    await t.pumpAndSettle();
    expect(repo.calls, isEmpty, reason: 'bấm Thôi thì không tạo đơn');

    await t.tap(find.byKey(const Key('plan-p1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('plan-confirm')));
    await t.pumpAndSettle();
    expect(repo.calls, ['request:p1']);
    expect(find.byKey(const Key('plan-pending')), findsOneWidget);
    expect(find.text('VGABC123'), findsOneWidget);
    expect(find.text('Ghi mã đơn khi chuyển khoản'), findsOneWidget);
    expect(find.text('Đang chờ xác nhận'), findsOneWidget);

    await t.tap(find.byKey(const Key('plan-cancel-order')));
    await t.pumpAndSettle();
    expect(repo.calls, ['request:p1', 'cancel']);
    expect(find.byKey(const Key('plan-p1')), findsOneWidget);
  });

  testWidgets('gói đã xác nhận: báo đang bật đến ngày nào', (t) async {
    final until = DateTime.now().add(const Duration(days: 20));
    final repo = FakePlans(
      PlanOverview(
        plans: const [_month],
        live: true,
        mine: PlanOrder(code: 'VGX', planName: 'Gói tháng', priceVnd: 99000, days: 30, status: PlanStatus.active, expiresAt: until),
      ),
    );
    await t.pumpWidget(host(repo));
    await t.pumpAndSettle();
    expect(find.text('Vy Live đang bật'), findsOneWidget);
    expect(find.text('Đến hết ngày ${formatDay(until)}.'), findsOneWidget);
    expect(find.text('Gia hạn thêm'), findsOneWidget);
  });

  testWidgets('người cao tuổi được người thân đăng ký: thấy tên người trả và có thanh Quay lại', (t) async {
    final repo = FakePlans(const PlanOverview(live: true, coveredBy: 'Lan'));
    await t.pumpWidget(host(repo, role: AppRole.elder));
    await t.pumpAndSettle();
    expect(find.text('Vy Live đang bật'), findsOneWidget);
    expect(find.text('Do Lan đăng ký cho bạn.'), findsOneWidget);
    expect(find.byKey(const Key('elder-back')), findsOneWidget);
  });
}
