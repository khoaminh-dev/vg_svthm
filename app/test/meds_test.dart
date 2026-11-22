import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/features/auth/domain/auth_user.dart';
import 'package:vg_svthm/features/auth/presentation/providers/auth_providers.dart';
import 'package:vg_svthm/features/meds/data/meds_repository.dart';
import 'package:vg_svthm/features/meds/domain/meds_models.dart';
import 'package:vg_svthm/features/meds/presentation/med_plan_edit_screen.dart';
import 'package:vg_svthm/features/meds/presentation/med_plan_list_screen.dart';
import 'package:vg_svthm/features/meds/presentation/meds_providers.dart';
import 'package:vg_svthm/features/meds/presentation/meds_view.dart';

class FakeMeds implements MedsRepository {
  FakeMeds({List<Dose>? doses, List<MedPlan>? plans})
    : doseList = doses ?? [],
      planList = plans ?? [];

  List<Dose> doseList;
  List<MedPlan> planList;
  final calls = <String>[];
  MedPlan? saved;
  bool? savedReplace;

  @override
  Future<List<MedPlan>> plans(String ownerId) async => List.of(planList);

  @override
  Future<List<Dose>> doses(String ownerId, DateTime from, DateTime to) async =>
      List.of(doseList);

  @override
  Future<String> savePlan(
    String ownerId,
    MedPlan plan, {
    bool replace = false,
  }) async {
    saved = plan;
    savedReplace = replace;
    calls.add('save');
    return 'new-plan';
  }

  @override
  Future<void> endPlan(String planId) async {
    calls.add('end:$planId');
    planList = [
      for (final p in planList)
        if (p.id == planId)
          MedPlan(
            id: p.id,
            title: p.title,
            startDate: p.startDate,
            active: false,
            slots: p.slots,
          )
        else
          p,
    ];
  }

  @override
  Future<void> setDose(String doseId, String status) async {
    calls.add('$status:$doseId');
    doseList = [
      for (final d in doseList)
        if (d.id == doseId)
          Dose(
            id: d.id,
            ownerId: d.ownerId,
            label: d.label,
            bag: d.bag,
            items: d.items,
            dueAt: d.dueAt,
            windowEnd: d.windowEnd,
            status: status,
            actedAt: status == 'pending' ? null : DateTime.now(),
          )
        else
          d,
    ];
  }

  @override
  Future<void> snooze(String doseId, int minutes) async =>
      calls.add('snooze:$doseId:$minutes');
}

Dose dose(
  String id,
  String label,
  DateTime due, {
  String status = 'pending',
  List<MedItem> items = const [],
  DateTime? acted,
  bool bag = true,
}) => Dose(
  id: id,
  ownerId: 'me',
  label: label,
  bag: bag,
  items: items,
  dueAt: due,
  windowEnd: due.add(const Duration(hours: 2)),
  status: status,
  actedAt: acted,
);

void bigScreen(WidgetTester t) {
  t.view.physicalSize = const Size(900, 2600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Widget host(Widget child, FakeMeds repo) => ProviderScope(
  key: UniqueKey(),
  overrides: [
    currentUserProvider.overrideWithValue(
      const AuthUser(id: 'me', username: 'minh'),
    ),
    medsRepositoryProvider.overrideWithValue(repo),
  ],
  child: MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: child),
  ),
);

void main() {
  orderTests();
  final now = DateTime(2026, 11, 16, 10, 0);

  group('trạng thái một lần uống', () {
    test('chưa tới giờ, đến giờ, quá giờ, đã uống, bỏ qua', () {
      final d = dose('a', 'Sáng', DateTime(2026, 11, 16, 12, 0));
      expect(d.stateAt(DateTime(2026, 11, 16, 10, 0)), DoseState.upcoming);
      expect(
        d.stateAt(DateTime(2026, 11, 16, 11, 40)),
        DoseState.due,
        reason: 'trước giờ 30 phút đã được bấm',
      );
      expect(d.stateAt(DateTime(2026, 11, 16, 13, 59)), DoseState.due);
      expect(
        d.stateAt(DateTime(2026, 11, 16, 14, 1)),
        DoseState.missed,
        reason: 'quá cửa sổ 2 giờ',
      );
      expect(
        dose('b', 'Sáng', now, status: 'taken').stateAt(now),
        DoseState.taken,
      );
      expect(
        dose('c', 'Sáng', now, status: 'skipped').stateAt(now),
        DoseState.skipped,
      );
      expect(
        dose('d', 'Sáng', now, status: 'missed').stateAt(now),
        DoseState.missed,
      );
    });

    test('mô tả thứ cần lấy: túi, thuốc trong túi, thuốc từ hũ', () {
      expect(dose('a', 'Sáng', now).what, 'túi Sáng');
      final d = dose(
        'a',
        'Sáng',
        now,
        items: const [
          MedItem(name: 'Amlodipin', strength: '5mg'),
          MedItem(name: 'Aspirin', fromJar: true),
        ],
      );
      expect(d.what, 'túi Sáng (Amlodipin), thêm từ hũ: Aspirin x1 viên');
      expect(
        d.spoken('bác'),
        'Đến giờ uống thuốc rồi bác ơi. bác lấy túi Sáng (Amlodipin), thêm từ hũ: Aspirin x1 viên nhé.',
      );
      expect(dose('a', 'Khuya', now, bag: false).what, 'thuốc buổi khuya');
    });

    test('MedItem.text bỏ số 0 thừa ở số lượng', () {
      expect(
        const MedItem(name: 'A', strength: '5mg', qty: 2).text,
        'A 5mg x2 viên',
      );
      expect(
        const MedItem(name: 'B', qty: 0.5, unit: 'viên').text,
        'B x0.5 viên',
      );
    });
  });

  test(
    'tuân thủ: chỉ tính các lần đã đến hạn, bỏ qua và chưa tới không tính',
    () {
      final doses = [
        dose('1', 'Sáng', DateTime(2026, 11, 15, 7), status: 'taken'),
        dose('2', 'Tối', DateTime(2026, 11, 15, 19), status: 'missed'),
        dose('3', 'Sáng', DateTime(2026, 11, 14, 7), status: 'skipped'),
        dose('4', 'Tối', DateTime(2026, 11, 16, 19)), // tương lai
        dose(
          '5',
          'Sáng',
          DateTime(2026, 11, 14, 7),
          status: 'pending',
        ), // quá cửa sổ → missed
      ];
      final a = Adherence.of(doses, now);
      expect(a.taken, 1);
      expect(a.total, 3);
      expect(a.rate, closeTo(1 / 3, 1e-9));
      expect(Adherence.of(const [], now).rate, isNull);
    },
  );

  test(
    'đơn thuốc: JSON đi và về giữ nguyên các cữ, thuốc và thuốc khi cần',
    () {
      final plan = MedPlan(
        title: 'Đơn thử',
        startDate: DateTime(2026, 11, 16),
        endDate: DateTime(2026, 12, 15),
        recheckDate: DateTime(2026, 12, 20),
        slots: const [
          MedSlot(
            label: 'Sáng',
            time: '07:00',
            mealRel: MealRel.afterMeal,
            bagsRemaining: 30,
            items: [MedItem(name: 'Amlodipin', strength: '5mg')],
          ),
          MedSlot(label: 'Tối', time: '20:30'),
        ],
        prn: const [
          MedPrn(
            name: 'Nitroglycerin',
            instruction: 'Ngậm khi đau ngực',
            maxPerDay: 3,
          ),
        ],
      );
      final j = plan.toJson();
      expect(j['start_date'], '2026-11-16');
      expect(j['end_date'], '2026-12-15');
      expect((j['slots'] as List).length, 2);
      expect((j['slots'] as List).first['meal_rel'], 'after_meal');
      expect((j['slots'] as List).first['mode'], 'bag');
      // đọc lại từ dạng PostgREST (med_slots/med_items/med_prn lồng nhau)
      final back = MedPlan.fromJson({
        'id': 'p1',
        'title': 'Đơn thử',
        'start_date': '2026-11-16',
        'end_date': '2026-12-15',
        'recheck_date': '2026-12-20',
        'status': 'active',
        'med_slots': [
          {
            'label': 'Tối',
            'time_local': '20:30:00',
            'mode': 'bag',
            'days_of_week': [1, 2, 3, 4, 5, 6, 7],
            'med_items': <Map<String, dynamic>>[],
          },
          {
            'label': 'Sáng',
            'time_local': '07:00:00',
            'mode': 'list',
            'meal_rel': 'after_meal',
            'bags_remaining': 30,
            'med_items': [
              {
                'name': 'Amlodipin',
                'strength': '5mg',
                'qty': 1,
                'unit': 'viên',
                'source': 'bag',
              },
            ],
          },
        ],
        'med_prn': [
          {
            'name': 'Nitroglycerin',
            'instruction': 'Ngậm khi đau ngực',
            'max_per_day': 3,
          },
        ],
      });
      expect(back.slots.map((s) => s.label), [
        'Sáng',
        'Tối',
      ], reason: 'sắp theo giờ');
      expect(back.slots.first.bag, isFalse);
      expect(back.slots.first.items.single.text, 'Amlodipin 5mg x1 viên');
      expect(back.slots.first.bagsRemaining, 30);
      expect(back.prn.single.maxPerDay, 3);
      expect(back.active, isTrue);
    },
  );

  testWidgets('màn Thuốc: chưa có lịch thì mời thêm', (t) async {
    bigScreen(t);
    await t.pumpWidget(host(const MedsView(), FakeMeds()));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('meds-empty')), findsOneWidget);
    expect(find.byKey(const Key('meds-add')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'màn Thuốc: cữ đến giờ có nút to Đã uống; bấm thì ghi nhận; có hoàn tác',
    (t) async {
      bigScreen(t);
      final n = DateTime.now();
      final repo = FakeMeds(
        doses: [
          dose(
            'd1',
            'Sáng',
            DateTime(n.year, n.month, n.day, 0, 5),
            status: 'taken',
            acted: n.subtract(const Duration(minutes: 30)),
            items: const [MedItem(name: 'Amlodipin', strength: '5mg')],
          ),
          dose(
            'd2',
            'Trưa',
            n.subtract(const Duration(minutes: 10)),
            items: const [MedItem(name: 'Aspirin', fromJar: true)],
          ),
          dose('d3', 'Tối', n.add(const Duration(hours: 6))),
        ],
        plans: [
          MedPlan(
            id: 'p1',
            title: 'Đơn thử',
            startDate: DateTime(n.year, n.month, n.day),
            recheckDate: DateTime(
              n.year,
              n.month,
              n.day,
            ).add(const Duration(days: 10)),
            slots: const [MedSlot(label: 'Sáng', time: '07:00')],
            prn: const [
              MedPrn(
                name: 'Nitroglycerin',
                instruction: 'Ngậm 1 viên khi đau ngực',
              ),
            ],
          ),
        ],
      );
      await t.pumpWidget(host(const MedsView(), repo));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('dose-d1')), findsOneWidget);
      expect(
        find.textContaining('Trong túi: Amlodipin 5mg x1 viên'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Lấy thêm từ hũ: Aspirin x1 viên'),
        findsOneWidget,
      );
      expect(find.text('Đến giờ uống thuốc'), findsOneWidget);
      expect(find.byKey(const Key('dose-taken-d2')), findsOneWidget);
      expect(
        find.byKey(const Key('dose-taken-d1')),
        findsNothing,
        reason: 'đã uống thì không còn nút',
      );
      expect(find.byKey(const Key('dose-undo-d1')), findsOneWidget);
      expect(find.text('Thuốc khi cần'), findsOneWidget);
      expect(find.text('Ngậm 1 viên khi đau ngực'), findsOneWidget);
      expect(find.text('10 ngày'), findsNothing);
      expect(find.textContaining('còn 10 ngày'), findsOneWidget);
      expect(find.byKey(const Key('meds-week')), findsOneWidget);

      await t.tap(find.byKey(const Key('dose-snooze-d2')));
      await t.pumpAndSettle();
      expect(repo.calls, contains('snooze:d2:15'));

      await t.tap(find.byKey(const Key('dose-taken-d2')));
      await t.pumpAndSettle();
      expect(repo.calls, contains('taken:d2'));
      expect(find.byKey(const Key('dose-taken-d2')), findsNothing);
      expect(find.byKey(const Key('dose-undo-d2')), findsOneWidget);

      await t.tap(find.byKey(const Key('dose-undo-d2')));
      await t.pumpAndSettle();
      expect(repo.calls, contains('pending:d2'));
      expect(find.byKey(const Key('dose-taken-d2')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('màn Thuốc: cữ quá giờ báo chưa uống và dặn không uống bù', (
    t,
  ) async {
    bigScreen(t);
    final n = DateTime.now();
    final repo = FakeMeds(
      doses: [
        dose(
          'm1',
          'Sáng',
          DateTime(n.year, n.month, n.day, 0, 1),
          status: 'missed',
        ),
      ],
      plans: [
        MedPlan(
          id: 'p1',
          title: 'Đơn',
          startDate: DateTime(n.year, n.month, n.day),
          slots: const [MedSlot(label: 'Sáng', time: '00:01')],
        ),
      ],
    );
    await t.pumpWidget(host(const MedsView(), repo));
    await t.pumpAndSettle();
    expect(find.text('Chưa uống, đã quá giờ'), findsOneWidget);
    expect(find.textContaining('đừng uống bù'), findsWidgets);
    expect(find.text('Tôi đã uống rồi'), findsWidgets, reason: 'cữ quá giờ vẫn ghi được là đã uống muộn');
    expect(find.byKey(const Key('dose-taken-m1')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'đặt lịch: chọn cữ, thêm thuốc trong túi và thuốc hũ, lưu đúng nội dung; thiếu cữ thì báo',
    (t) async {
      bigScreen(t);
      final repo = FakeMeds();
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/edit',
            builder: (_, _) => const MedPlanEditScreen(ownerId: 'me'),
          ),
          GoRoute(path: '/', builder: (_, _) => const Text('XONG')),
        ],
      );
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(
              const AuthUser(id: 'me', username: 'minh'),
            ),
            medsRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await t.pumpAndSettle();
      unawaited(router.push('/edit'));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('plan-save')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('plan-error')), findsOneWidget);
      expect(repo.saved, isNull);

      await t.tap(find.byKey(const Key('preset-Sáng')));
      await t.tap(find.byKey(const Key('preset-Tối')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('slot-0')), findsOneWidget);
      expect(find.byKey(const Key('slot-1')), findsOneWidget);

      await t.ensureVisible(find.byKey(const Key('item-add-0')));
      await t.tap(find.byKey(const Key('item-add-0')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('item-name')), 'Amlodipin');
      await t.enterText(find.byKey(const Key('item-strength')), '5mg');
      await t.tap(find.byKey(const Key('item-ok')));
      await t.pumpAndSettle();
      expect(find.text('Amlodipin 5mg x1 viên'), findsOneWidget);

      await t.tap(find.byKey(const Key('item-add-0')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('item-name')), 'Aspirin');
      await t.tap(find.byKey(const Key('item-jar')));
      await t.tap(find.byKey(const Key('item-ok')));
      await t.pumpAndSettle();
      expect(find.text('Lấy thêm từ hũ'), findsOneWidget);

      await t.tap(find.byKey(const Key('days-14')));
      await t.ensureVisible(find.byKey(const Key('plan-save')));
      await t.tap(find.byKey(const Key('plan-save')));
      await t.pumpAndSettle();

      final p = repo.saved!;
      expect(p.slots.map((s) => s.label), ['Sáng', 'Tối']);
      expect(p.slots.first.items.map((i) => i.name), ['Amlodipin', 'Aspirin']);
      expect(p.slots.first.items.last.fromJar, isTrue);
      expect(p.slots.first.bagsRemaining, 14, reason: 'số túi bằng số ngày');
      expect(p.endDate!.difference(p.startDate).inDays, 13);
      expect(repo.savedReplace, isFalse);
      expect(find.text('XONG'), findsOneWidget);
    },
  );

  testWidgets(
    'đặt lịch: đang có đơn khác thì hỏi dừng đơn cũ, chọn dừng thì gửi replace',
    (t) async {
      bigScreen(t);
      final repo = FakeMeds(
        plans: [
          MedPlan(
            id: 'old',
            title: 'Đơn cũ',
            startDate: DateTime(2026, 11, 1),
            slots: const [MedSlot(label: 'Sáng', time: '07:00')],
          ),
        ],
      );
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/edit',
            builder: (_, _) => const MedPlanEditScreen(ownerId: 'me'),
          ),
          GoRoute(path: '/', builder: (_, _) => const Text('XONG')),
        ],
      );
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(
              const AuthUser(id: 'me', username: 'minh'),
            ),
            medsRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await t.pumpAndSettle();
      unawaited(router.push('/edit'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('preset-Sáng')));
      await t.pump();
      await t.ensureVisible(find.byKey(const Key('plan-save')));
      await t.tap(find.byKey(const Key('plan-save')));
      await t.pumpAndSettle();
      expect(find.text('Dừng đơn cũ?'), findsOneWidget);
      await t.tap(find.byKey(const Key('replace-stop')));
      await t.pumpAndSettle();
      expect(repo.savedReplace, isTrue);
    },
  );

  testWidgets('danh sách đơn: hiện đơn, kết thúc có hỏi lại', (t) async {
    bigScreen(t);
    final repo = FakeMeds(
      plans: [
        MedPlan(
          id: 'p1',
          title: 'Đơn tim mạch',
          startDate: DateTime(2026, 11, 1),
          endDate: DateTime(2026, 11, 30),
          slots: const [
            MedSlot(
              label: 'Sáng',
              time: '07:00',
              items: [MedItem(name: 'Amlodipin')],
            ),
          ],
        ),
      ],
    );
    await t.pumpWidget(host(const MedPlanListScreen(ownerId: 'me'), repo));
    await t.pumpAndSettle();
    expect(find.text('Đơn tim mạch'), findsOneWidget);
    expect(find.text('Đang dùng'), findsOneWidget);
    expect(find.textContaining('07:00  Túi Sáng: Amlodipin'), findsOneWidget);

    await t.tap(find.byKey(const Key('plan-end-p1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('end-cancel')));
    await t.pumpAndSettle();
    expect(repo.calls.where((c) => c.startsWith('end')), isEmpty);
    await t.tap(find.byKey(const Key('plan-end-p1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('end-confirm')));
    await t.pumpAndSettle();
    expect(repo.calls, contains('end:p1'));
    expect(find.text('Đã kết thúc'), findsOneWidget);
  });
}

void orderTests() {
  test('byTime sắp theo giờ tăng dần dù máy chủ trả ngược', () {
    final d1 = dose('1', 'Sáng', DateTime(2026, 11, 16, 7));
    final d2 = dose('2', 'Tối', DateTime(2026, 11, 16, 20));
    final d3 = dose('3', 'Trưa', DateTime(2026, 11, 16, 12));
    expect(byTime([d2, d3, d1]).map((d) => d.id), ['1', '3', '2']);
  });
}
