import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/features/auth/domain/auth_user.dart';
import 'package:vg_svthm/features/auth/presentation/providers/auth_providers.dart';
import 'package:vg_svthm/features/bp/domain/bp_models.dart';
import 'package:vg_svthm/features/bp/domain/bp_repository.dart';
import 'package:vg_svthm/features/bp/presentation/providers/bp_providers.dart';
import 'package:vg_svthm/features/family/data/family_repository.dart';
import 'package:vg_svthm/features/family/domain/family_models.dart';
import 'package:vg_svthm/features/family/domain/family_status.dart';
import 'package:vg_svthm/features/family/presentation/family_audit_screen.dart';
import 'package:vg_svthm/features/family/presentation/family_home_screen.dart';
import 'package:vg_svthm/features/family/presentation/family_invite_screen.dart';
import 'package:vg_svthm/features/family/presentation/family_join_screen.dart';
import 'package:vg_svthm/features/family/presentation/family_person_screen.dart';
import 'package:vg_svthm/features/family/presentation/family_providers.dart';
import 'package:vg_svthm/features/health/data/health_repository.dart';
import 'package:vg_svthm/features/health/domain/health_models.dart';
import 'package:vg_svthm/features/health/presentation/providers/health_providers.dart';
import 'package:vg_svthm/features/meds/domain/meds_models.dart';
import 'package:vg_svthm/features/meds/presentation/meds_providers.dart';
import 'package:vg_svthm/features/profile/data/phone_repository.dart';
import 'package:vg_svthm/features/profile/data/phone_repository.dart';
import 'package:vg_svthm/features/push/push_service.dart';
import 'package:vg_svthm/features/safety/presentation/sos_widgets.dart' show phoneLauncherProvider;
import 'package:vg_svthm/features/safety/presentation/sos_widgets.dart' show phoneLauncherProvider;

import 'health_test.dart' show FakeHealthRepository;
import 'meds_test.dart' show FakeMeds, dose;

class FakeFamily implements FamilyRepository {
  FakeFamily({List<FamilyLink>? links}) : links = links ?? [];

  List<FamilyLink> links;
  String code = '123456';
  RedeemResult redeemResult = const RedeemResult(linkId: 'l-new');
  final calls = <String>[];
  Map<String, bool>? lastPerms;
  String? lastStatus;
  String nudgeResult = 'ok';
  List<AuditEntry> auditList = [];

  @override
  Future<List<FamilyLink>> myFamily() async => List.of(links);

  @override
  Future<String> createCode() async {
    calls.add('createCode');
    return code;
  }

  @override
  Future<RedeemResult> redeem(String c, Relation relation) async {
    calls.add('redeem:$c:${relation.code}');
    return redeemResult;
  }

  @override
  Future<void> revoke(String linkId) async {
    calls.add('revoke:$linkId');
    links = [
      for (final l in links)
        if (l.linkId != linkId) l,
    ];
  }

  @override
  Future<void> setPerms(
    String linkId, {
    Map<String, bool>? perms,
    String? status,
  }) async {
    calls.add('setPerms:$linkId');
    lastPerms = perms;
    lastStatus = status;
  }

  @override
  Future<List<AuditEntry>> audit({int limit = 50}) async => auditList;

  @override
  Future<String> nudgeMeasure(String ownerId) async {
    calls.add('nudge:$ownerId');
    return nudgeResult;
  }
}

class FakeBp implements BpRepository {
  FakeBp(this.byOwner);

  @override
  Future<void> markSymptoms(String sessionId, List<String> symptoms) async {}

  @override
  Future<void> markContext(String sessionId, List<String> context) async {}

  final Map<String, List<BpReading>> byOwner;

  @override
  Future<List<BpReading>> list({int limit = 200, String? ownerId}) async =>
      byOwner[ownerId] ?? const [];

  @override
  Future<void> add(BpReading reading) async {}

  @override
  Future<void> delete(String id) async {}
}

FamilyLink link(
  String id, {
  String role = 'carer',
  String other = 'p1',
  String name = 'Nguyễn Thị Lan',
  String status = 'active',
  Map<String, bool>? perms,
  String? username = 'lan',
}) => FamilyLink(
  linkId: id,
  role: role,
  otherId: other,
  otherName: name,
  otherUsername: username,
  relation: Relation.con,
  perms:
      perms ??
      {
        for (final k in FamilyPerm.labels.keys)
          k: k != FamilyPerm.profileEdit && k != FamilyPerm.vyHistory,
      },
  status: status,
  createdAt: DateTime(2026, 11, 1),
);

BpReading bp(int s, int d, DateTime at, {int? pulse}) =>
    BpReading(systolic: s, diastolic: d, pulse: pulse, measuredAt: at);

void bigScreen(WidgetTester t) {
  t.view.physicalSize = const Size(900, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Widget host(
  Widget child, {
  required FakeFamily fam,
  FakeBp? bpRepo,
  HealthRepository? health,
  FakeMeds? meds,
  List<Override> extra = const [],
}) => ProviderScope(
  key: UniqueKey(),
  overrides: [
    currentUserProvider.overrideWithValue(
      const AuthUser(id: 'me', username: 'minh'),
    ),
    familyRepositoryProvider.overrideWithValue(fam),
    bpRepositoryProvider.overrideWithValue(bpRepo ?? FakeBp({})),
    healthRepositoryProvider.overrideWithValue(
      health ?? FakeHealthRepository(),
    ),
    medsRepositoryProvider.overrideWithValue(meds ?? FakeMeds()),
    ...extra,
  ],
  child: MaterialApp(theme: AppTheme.light, home: child),
);

void main() {
  SharedPreferences.setMockInitialValues({});
  final now = DateTime(2026, 11, 16, 10);

  group('đèn trạng thái', () {
    test('xanh khi số đo bình thường và mới', () {
      final s = computeFamilyStatus(
        readings: [bp(120, 80, now.subtract(const Duration(hours: 2)))],
        now: now,
      );
      expect(s.light, FamilyLight.green);
      expect(s.reasons, isEmpty);
    });

    test('đỏ khi từ 180/120 trong 24 giờ; số đo cũ hơn thì không đỏ', () {
      expect(
        computeFamilyStatus(
          readings: [bp(185, 100, now.subtract(const Duration(hours: 3)))],
          now: now,
        ).light,
        FamilyLight.red,
      );
      expect(
        computeFamilyStatus(
          readings: [bp(150, 125, now.subtract(const Duration(hours: 3)))],
          now: now,
        ).light,
        FamilyLight.red,
      );
      final old = computeFamilyStatus(
        readings: [bp(190, 110, now.subtract(const Duration(days: 2)))],
        now: now,
      );
      expect(old.light, isNot(FamilyLight.red));
    });

    test(
      'vàng khi cao hai lần liên tiếp, chưa đo lâu, hoặc chưa đo lần nào',
      () {
        final two = computeFamilyStatus(
          readings: [
            bp(150, 95, now.subtract(const Duration(hours: 1))),
            bp(145, 92, now.subtract(const Duration(days: 1))),
          ],
          now: now,
        );
        expect(two.light, FamilyLight.yellow);
        expect(two.reasons.first, contains('hai lần liên tiếp'));
        expect(
          computeFamilyStatus(
            readings: [bp(120, 80, now.subtract(const Duration(days: 5)))],
            now: now,
          ).reasons.first,
          contains('5 ngày'),
        );
        expect(
          computeFamilyStatus(readings: const [], now: now).reasons.first,
          contains('Chưa đo huyết áp lần nào'),
        );
        // một lần cao đơn lẻ chưa đáng báo vàng
        expect(
          computeFamilyStatus(
            readings: [
              bp(150, 95, now.subtract(const Duration(hours: 1))),
              bp(120, 80, now.subtract(const Duration(days: 1))),
            ],
            now: now,
          ).light,
          FamilyLight.green,
        );
      },
    );

    test('nguy cơ cao thì vàng; khẩn cấp mới và còn hiệu lực thì đỏ', () {
      RiskResult risk(RiskLevel l, DateTime at) => RiskResult(
        level: l,
        reasons: const [],
        systolic: 150,
        diastolic: 95,
        measuredAt: at,
        createdAt: at,
      );
      final r = [bp(130, 85, now.subtract(const Duration(hours: 1)))];
      expect(
        computeFamilyStatus(
          readings: r,
          risk: risk(RiskLevel.high, r.first.measuredAt),
          now: now,
        ).light,
        FamilyLight.yellow,
      );
      expect(
        computeFamilyStatus(
          readings: r,
          risk: risk(RiskLevel.urgent, r.first.measuredAt),
          now: now,
        ).light,
        FamilyLight.red,
      );
      // đánh giá khẩn cấp của lần đo cũ hơn số đo gần nhất thì không báo đỏ
      expect(
        computeFamilyStatus(
          readings: r,
          risk: risk(RiskLevel.urgent, now.subtract(const Duration(days: 2))),
          now: now,
        ).light,
        isNot(FamilyLight.red),
      );
    });

    test('đỏ liệt kê cả lý do vàng đi kèm, lý do đỏ đứng đầu', () {
      final s = computeFamilyStatus(
        readings: [bp(190, 110, now.subtract(const Duration(hours: 1)))],
        now: now,
      );
      expect(s.reasons.first, contains('rất cao'));
      expect(s.headline, 'Cần chú ý ngay');
    });
  });

  test('FamilyLink đọc từ my_family; quyền và tên hiển thị', () {
    final l = FamilyLink.fromMap({
      'link_id': 'a',
      'role': 'owner',
      'other_id': 'u',
      'other_name': '  ',
      'other_username': 'minh',
      'relation': 'vo_chong',
      'perms': {'health': true, 'meds_edit': false, 'x': 'bậy'},
      'status': 'paused',
      'created_at': '2026-11-01T00:00:00Z',
    });
    expect(l.iAmOwner, isTrue);
    expect(l.active, isFalse);
    expect(l.name, 'minh');
    expect(l.relation, Relation.voChong);
    expect(l.can(FamilyPerm.health), isTrue);
    expect(l.can(FamilyPerm.medsEdit), isFalse);
    expect(l.perms.containsKey('x'), isFalse);
    expect(
      const RedeemResult(error: 'invalid_code').message,
      contains('hết hạn'),
    );
    expect(const RedeemResult(linkId: 'x').ok, isTrue);
  });

  test('bấm thông báo mở đúng màn', () {
    expect(
      PushService.pathFor({'type': 'message', 'room_id': 'r1'}),
      '/rooms/r1',
    );
    expect(
      PushService.pathFor({'type': 'family_alert', 'owner_id': 'p1'}),
      '/family/person/p1',
    );
    expect(PushService.pathFor({'type': 'nudge'}), '/measure');
    expect(PushService.pathFor({'type': 'update'}), isNull);
    expect(PushService.pathFor({'type': 'message'}), isNull);
    expect(PushService.pathFor({}), isNull);
  });

  testWidgets(
    'mời người thân: tạo mã, hiện mã và đếm ngược; không có ai thì nói rõ',
    (t) async {
      bigScreen(t);
      final fam = FakeFamily();
      await t.pumpWidget(host(const FamilyInviteScreen(), fam: fam));
      await t.pumpAndSettle();
      expect(find.text('Chưa có ai theo dõi'), findsOneWidget);
      expect(find.byKey(const Key('invite-code')), findsNothing);

      await t.tap(find.byKey(const Key('invite-create')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(fam.calls, contains('createCode'));
      expect(find.text('123 456'), findsOneWidget);
      expect(find.text('Còn 10:00'), findsOneWidget);
      await t.pump(const Duration(seconds: 2));
      // dọn bộ đếm của màn hình
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('người đang theo dõi: đổi quyền, tạm dừng, gỡ có hỏi lại', (
    t,
  ) async {
    bigScreen(t);
    final fam = FakeFamily(
      links: [link('l1', role: 'owner', other: 'c1', name: 'Con Minh')],
    );
    await t.pumpWidget(host(const FamilyInviteScreen(), fam: fam));
    await t.pumpAndSettle();
    expect(find.text('Đang theo dõi bác (1)'), findsOneWidget);

    await t.tap(find.byKey(const Key('watcher-l1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('perm-l1-location')));
    await t.pumpAndSettle();
    expect(fam.calls, contains('setPerms:l1'));
    expect(fam.lastPerms, {'location': false});

    await t.tap(find.byKey(const Key('pause-l1')));
    await t.pumpAndSettle();
    expect(fam.lastStatus, 'paused');

    await t.ensureVisible(find.byKey(const Key('revoke-l1')));
    await t.tap(find.byKey(const Key('revoke-l1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('revoke-cancel')));
    await t.pumpAndSettle();
    expect(fam.calls.where((c) => c.startsWith('revoke')), isEmpty);
    await t.tap(find.byKey(const Key('revoke-l1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('revoke-confirm')));
    await t.pumpAndSettle();
    expect(fam.calls, contains('revoke:l1'));
    expect(find.text('Chưa có ai theo dõi'), findsOneWidget);
  });

  testWidgets(
    'nhập mã: sai độ dài, mã sai báo lỗi, mã đúng thì liên kết và về Trang chủ',
    (t) async {
      bigScreen(t);
      final fam = FakeFamily(links: [link('l-new')]);
      final router = GoRouter(
        initialLocation: '/join',
        routes: [
          GoRoute(path: '/join', builder: (_, _) => const FamilyJoinScreen()),
          GoRoute(path: '/', builder: (_, _) => const Text('TRANG CHU')),
        ],
      );
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(
              const AuthUser(id: 'me', username: 'minh'),
            ),
            familyRepositoryProvider.overrideWithValue(fam),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await t.pumpAndSettle();

      await t.enterText(find.byKey(const Key('join-code')), '123');
      await t.tap(find.byKey(const Key('join-submit')));
      await t.pumpAndSettle();
      expect(find.text('Mã gồm 6 chữ số.'), findsOneWidget);
      expect(fam.calls.where((c) => c.startsWith('redeem')), isEmpty);

      fam.redeemResult = const RedeemResult(error: 'invalid_code');
      await t.enterText(find.byKey(const Key('join-code')), '123 456');
      await t.tap(find.byKey(const Key('join-submit')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('join-error')), findsOneWidget);
      expect(find.textContaining('hết hạn'), findsOneWidget);

      fam.redeemResult = const RedeemResult(linkId: 'l-new');
      await t.tap(find.byKey(const Key('rel-chau')));
      await t.pump();
      await t.tap(find.byKey(const Key('join-submit')));
      await t.pumpAndSettle();
      expect(fam.calls.last, 'redeem:123456:chau');
      expect(find.text('TRANG CHU'), findsOneWidget);
    },
  );

  testWidgets('nút Gọi: chỉ hiện khi người thân có số; bấm là mở trình gọi với đúng số', (t) async {
    bigScreen(t);
    final dialed = <String>[];
    final fam = FakeFamily(links: [link('l1'), link('l2', other: 'p2', name: 'Trần Văn Hùng')]);
    await t.pumpWidget(
      host(
        const FamilyHomeScreen(),
        fam: fam,
        extra: [
          personPhoneProvider('p1').overrideWith((ref) async => '0901 234 567'),
          personPhoneProvider('p2').overrideWith((ref) async => null),
          phoneLauncherProvider.overrideWithValue((n) async => dialed.add(n)),
        ],
      ),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('call-p1')), findsOneWidget);
    expect(find.byKey(const Key('call-p2')), findsNothing, reason: 'chưa có số thì ẩn nút');
    await t.tap(find.byKey(const Key('call-p1')));
    await t.pump();
    expect(dialed, ['0901 234 567']);
  });

  testWidgets(
    'màn Gia đình: rỗng thì mời nhập mã; có người thì hiện đèn, huyết áp và nút nhờ đo',
    (t) async {
      bigScreen(t);
      await t.pumpWidget(host(const FamilyHomeScreen(), fam: FakeFamily()));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('family-empty')), findsOneWidget);

      final fam = FakeFamily(
        links: [
          link('l1'),
          link(
            'l2',
            other: 'p2',
            name: 'Trần Văn Hùng',
            perms: {FamilyPerm.health: false},
          ),
        ],
      );
      final recent = DateTime.now().subtract(const Duration(minutes: 30));
      final bpRepo = FakeBp({
        'p1': [
          bp(188, 115, recent),
          bp(130, 80, recent.subtract(const Duration(days: 1))),
        ],
        'p2': [bp(120, 78, recent)],
      });
      await t.pumpWidget(
        host(const FamilyHomeScreen(), fam: fam, bpRepo: bpRepo),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('person-card-p1')), findsOneWidget);
      expect(find.text('Nguyễn Thị Lan'), findsOneWidget);
      expect(find.text('188/115'), findsOneWidget);
      expect(
        find.text('Cần chú ý ngay'),
        findsOneWidget,
        reason: 'Lan có số đo rất cao',
      );
      expect(find.text('Ổn'), findsOneWidget, reason: 'Hùng bình thường');
      expect(find.text('Huyết áp rất cao (188/115)'), findsOneWidget);
      // người không cấp quyền xem sức khoẻ thì không có nút nhờ đo
      expect(find.byKey(const Key('nudge-p1')), findsOneWidget);
      expect(find.byKey(const Key('nudge-p2')), findsNothing);

      await t.tap(find.byKey(const Key('nudge-p1')));
      await t.pumpAndSettle();
      expect(fam.calls, contains('nudge:p1'));
      expect(find.textContaining('Đã nhắc'), findsOneWidget);
      await t.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'chi tiết người thân: số đo mới nhất, nguy cơ, hồ sơ; người đã gỡ thì báo không còn theo dõi',
    (t) async {
      bigScreen(t);
      final fam = FakeFamily(links: [link('l1')]);
      final at = DateTime.now().subtract(const Duration(hours: 2));
      final health = FakeHealthRepository(
        profile: const HealthProfile(
          birthYear: 1950,
          sex: 'female',
          hypertension: true,
          diabetes: true,
          heightCm: 155,
          weightKg: 58,
        ),
        risk: RiskResult(
          level: RiskLevel.attention,
          reasons: const ['hypertension'],
          systolic: 150,
          diastolic: 95,
          measuredAt: at,
          createdAt: at,
          strokeP: 0.12,
          strokeLevel: RiskLevel.high,
          heartP: 0.25,
          ageOutOfRange: true,
          heartLevel: RiskLevel.attention,
        ),
      );
      final bpRepo = FakeBp({
        'p1': [
          bp(150, 95, at, pulse: 74),
          bp(146, 92, at.subtract(const Duration(days: 1))),
          bp(138, 88, at.subtract(const Duration(days: 2))),
        ],
      });
      await t.pumpWidget(
        host(
          const FamilyPersonScreen(ownerId: 'p1'),
          fam: fam,
          bpRepo: bpRepo,
          health: health,
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Nguyễn Thị Lan'), findsWidgets);
      expect(find.text('150/95 mmHg'), findsOneWidget);
      expect(find.textContaining('Mạch 74'), findsOneWidget);
      expect(find.byKey(const Key('person-banner')), findsOneWidget);
      expect(find.byKey(const Key('person-age-note')), findsOneWidget);
      expect(
        find.text('Huyết áp cao hai lần liên tiếp (150/95)'),
        findsOneWidget,
      );
      await t.scrollUntilVisible(
        find.byKey(const Key('person-profile')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Tiểu đường'), findsWidgets);
      expect(find.text('155 cm · 58 kg'), findsOneWidget);
      expect(find.text('12%'), findsOneWidget, reason: 'vòng đột quỵ');

      await t.pumpWidget(
        host(const FamilyPersonScreen(ownerId: 'p1'), fam: FakeFamily()),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('person-gone')), findsOneWidget);
    },
  );

  testWidgets('nhật ký gia đình: hiện từng dòng; trống thì nói rõ', (t) async {
    bigScreen(t);
    await t.pumpWidget(host(const FamilyAuditScreen(), fam: FakeFamily()));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('audit-empty')), findsOneWidget);

    final fam = FakeFamily()
      ..auditList = [
        AuditEntry(
          id: 2,
          action: 'link_created',
          at: DateTime(2026, 11, 16, 9, 5),
          actorName: 'Con Minh',
        ),
        AuditEntry(
          id: 1,
          action: 'perms_changed',
          at: DateTime(2026, 11, 15, 20, 0),
        ),
      ];
    await t.pumpWidget(host(const FamilyAuditScreen(), fam: fam));
    await t.pumpAndSettle();
    expect(
      find.text('Con Minh đã được thêm vào danh sách theo dõi'),
      findsOneWidget,
    );
    expect(
      find.text('Bạn đã đổi quyền của một người theo dõi'),
      findsOneWidget,
    );
    expect(find.text('09:05 ngày 16/11'), findsOneWidget);
  });
  testWidgets(
    'chi tiết người thân: thuốc hôm nay, tuân thủ 7 ngày, nút sửa lịch theo quyền',
    (t) async {
      bigScreen(t);
      final n = DateTime.now();
      final meds = FakeMeds(
        doses: [
          dose(
            'a',
            'Sáng',
            DateTime(n.year, n.month, n.day, 0, 5),
            status: 'taken',
          ),
          dose(
            'b',
            'Tối',
            DateTime(
              n.year,
              n.month,
              n.day,
            ).add(const Duration(hours: 23, minutes: 59)),
          ),
          dose(
            'c',
            'Sáng',
            DateTime(
              n.year,
              n.month,
              n.day,
            ).subtract(const Duration(days: 1)).add(const Duration(hours: 7)),
            status: 'missed',
          ),
        ],
        plans: [
          MedPlan(
            id: 'p',
            title: 'Đơn',
            startDate: DateTime(n.year, n.month, n.day),
            slots: const [MedSlot(label: 'Sáng', time: '07:00')],
          ),
        ],
      );
      final bpRepo = FakeBp({
        'p1': [bp(120, 80, DateTime.now().subtract(const Duration(hours: 1)))],
      });

      await t.pumpWidget(
        host(
          const FamilyPersonScreen(ownerId: 'p1'),
          fam: FakeFamily(links: [link('l1')]),
          bpRepo: bpRepo,
          meds: meds,
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const Key('person-adherence')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Thuốc hôm nay'), findsOneWidget);
      expect(find.byKey(const Key('person-dose-a')), findsOneWidget);
      expect(find.text('Đã uống'), findsOneWidget);
      // Cữ cuối ngày là 'Sắp tới', hoặc 'Đến giờ' nếu đang chạy test sát nửa đêm (nằm trong cửa sổ sớm).
    expect(find.textContaining(RegExp('Sắp tới|Đến giờ')), findsOneWidget);
      expect(
        find.textContaining('7 ngày qua: uống 1/2 cữ (50%)'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('person-meds-manage')), findsOneWidget);

      // Không có quyền sửa thuốc thì không có nút sửa lịch; không có quyền xem thuốc thì không có cả thẻ.
      final noEdit = link(
        'l1',
        perms: {
          FamilyPerm.health: true,
          FamilyPerm.medsView: true,
          FamilyPerm.medsEdit: false,
        },
      );
      await t.pumpWidget(
        host(
          const FamilyPersonScreen(ownerId: 'p1'),
          fam: FakeFamily(links: [noEdit]),
          bpRepo: bpRepo,
          meds: meds,
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const Key('person-adherence')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('person-meds-manage')), findsNothing);

      final noView = link(
        'l1',
        perms: {FamilyPerm.health: true, FamilyPerm.medsView: false},
      );
      await t.pumpWidget(
        host(
          const FamilyPersonScreen(ownerId: 'p1'),
          fam: FakeFamily(links: [noView]),
          bpRepo: bpRepo,
          meds: meds,
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Thuốc hôm nay'), findsNothing);
    },
  );
}
