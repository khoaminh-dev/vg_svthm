import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vg_svthm/app.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/features/auth/domain/auth_user.dart';
import 'package:vg_svthm/features/auth/presentation/providers/auth_providers.dart';
import 'package:vg_svthm/features/bp/presentation/providers/bp_providers.dart';
import 'package:vg_svthm/features/health/data/health_repository.dart';
import 'package:vg_svthm/features/health/domain/health_models.dart';
import 'package:vg_svthm/features/health/presentation/providers/health_providers.dart';
import 'package:vg_svthm/features/health/presentation/screens/health_setup_screen.dart';
import 'package:vg_svthm/features/health/presentation/widgets/risk_view.dart';

import 'auth_flow_test.dart' show FakeAuthRepository, settle;

class FakeHealthRepository implements HealthRepository {
  FakeHealthRepository({this.profile, this.risk});

  HealthProfile? profile;
  RiskResult? risk;
  int runs = 0;

  @override
  Future<HealthProfile?> getProfile() async => profile;

  @override
  Future<void> saveProfile(HealthProfile p) async => profile = p;

  @override
  Future<RiskResult?> latestAssessment() async => risk;

  @override
  Future<RiskResult?> runAssessment() async {
    runs++;
    return risk;
  }
}

RiskResult result(
  RiskLevel level, {
  List<String> reasons = const [],
  int sys = 150,
  int dia = 95,
  bool oldAge = false,
}) => RiskResult(
  level: level,
  reasons: reasons,
  systolic: sys,
  diastolic: dia,
  measuredAt: DateTime(2026, 11, 14, 8, 10),
  createdAt: DateTime(2026, 11, 14, 8, 11),
  ageOutOfRange: oldAge,
);

void bigScreen(WidgetTester t) {
  t.view.physicalSize = const Size(900, 2200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  test('RiskResult đọc được JSON của API và cột details', () {
    final r = RiskResult.fromJson({
      'level': 'attention',
      'reasons': ['smoker', 'age_65'],
      'bp': {
        'systolic': 150,
        'diastolic': 95,
        'pulse': 70,
        'measuredAt': '2026-11-14T01:10:00Z',
      },
      'ageOutOfRange': true,
      'createdAt': '2026-11-14T01:11:00Z',
    });
    expect(r.level, RiskLevel.attention);
    expect(r.reasons, ['smoker', 'age_65']);
    expect(r.systolic, 150);
    expect(r.ageOutOfRange, isTrue);
    expect(RiskLevel.of('urgent'), RiskLevel.urgent);
    expect(RiskLevel.of('lạ'), RiskLevel.low);
    expect(RiskLevel.low.worthMentioning, isFalse);
    expect(RiskLevel.attention.worthMentioning, isTrue);
  });

  testWidgets(
    'thiết lập lần đầu: 2 màn, mặc định "Không", đồng ý ngay trên nút Hoàn tất',
    (t) async {
      bigScreen(t);
      final repo = FakeHealthRepository();
      final router = GoRouter(
        initialLocation: '/health-setup',
        routes: [
          GoRoute(
            path: '/health-setup',
            builder: (_, _) => const HealthSetupScreen(),
          ),
          GoRoute(path: '/', builder: (_, _) => const Text('TRANG CHU')),
        ],
      );
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(
              const AuthUser(id: 'u1', username: 'an'),
            ),
            healthRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await t.pumpAndSettle();

      expect(find.text('Bước 1/2'), findsOneWidget);
      // Chưa chọn giới tính: bấm tiếp tục vẫn ở bước 1.
      await t.tap(find.byKey(const Key('health-next')));
      await t.pumpAndSettle();
      expect(find.text('Bước 1/2'), findsOneWidget);
      expect(find.byKey(const Key('sex-error')), findsOneWidget);

      await t.tap(find.byKey(const Key('sex-female')));
      await t.pump();
      expect(find.byKey(const Key('sex-error')), findsNothing);
      await t.tap(find.byKey(const Key('health-next')));
      await t.pumpAndSettle();

      // Màn cuối: đủ các câu trên một màn, câu thuốc huyết áp chưa hiện, có dòng đồng ý và nút Hoàn tất.
      expect(find.text('Bước 2/2'), findsOneWidget);
      expect(find.text('Đang hút thuốc'), findsOneWidget);
      expect(find.text('Từng bị đột quỵ'), findsOneWidget);
      expect(find.byKey(const Key('bpMeds-yes')), findsNothing);
      expect(find.byKey(const Key('health-consent')), findsOneWidget);
      expect(find.text('Hoàn tất'), findsOneWidget);

      await t.tap(find.byKey(const Key('hypertension-yes')));
      await t.pump();
      expect(find.byKey(const Key('bpMeds-yes')), findsOneWidget);
      await t.tap(find.byKey(const Key('bpMeds-yes')));
      await t.tap(find.byKey(const Key('diabetes-yes')));
      await t.tap(find.byKey(const Key('health-next')));
      await t.pumpAndSettle();

      final p = repo.profile!;
      expect(p.sex, 'female');
      expect(p.hypertension, isTrue);
      expect(p.bpMeds, isTrue);
      expect(p.diabetes, isTrue);
      expect(p.smoker, isFalse);
      expect(p.birthYear, 1955);
      expect(find.text('TRANG CHU'), findsOneWidget);
    },
  );

  testWidgets('tab Đánh giá: mức, câu kết luận, lý do gập lại', (t) async {
    bigScreen(t);
    final repo = FakeHealthRepository(
      risk: result(
        RiskLevel.attention,
        reasons: ['bp_high_now', 'smoker'],
        oldAge: true,
      ),
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          healthRepositoryProvider.overrideWithValue(repo),
          bpReadingsProvider.overrideWith((ref) async => []),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: RiskView()),
        ),
      ),
    );
    await t.pumpAndSettle();

    expect(find.text('Cần chú ý'), findsOneWidget);
    expect(find.textContaining('Dựa trên huyết áp 150/95'), findsOneWidget);
    expect(find.text('Gọi 115'), findsNothing);
    expect(repo.runs, 1, reason: 'mở tab thì làm mới ngầm một lần');

    expect(find.text('Bác đang hút thuốc'), findsNothing);
    await t.tap(find.text('Vì sao có kết quả này'));
    await t.pumpAndSettle();
    expect(find.text('Bác đang hút thuốc'), findsOneWidget);
    expect(
      find.textContaining('Huyết áp lần đo gần nhất khá cao'),
      findsOneWidget,
    );
    expect(find.textContaining('trên 70 tuổi'), findsOneWidget);
  });

  testWidgets(
    'mức khẩn cấp có nút Gọi 115; chưa có đánh giá thì mời đo huyết áp',
    (t) async {
      bigScreen(t);
      Future<void> pump(
        FakeHealthRepository repo, {
        List<Never> readings = const [],
      }) async {
        await t.pumpWidget(
          ProviderScope(
            overrides: [
              healthRepositoryProvider.overrideWithValue(repo),
              bpReadingsProvider.overrideWith((ref) async => readings),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: const Scaffold(body: RiskView()),
            ),
          ),
        );
        await t.pumpAndSettle();
      }

      await pump(
        FakeHealthRepository(
          risk: result(RiskLevel.urgent, sys: 190, dia: 110),
        ),
      );
      expect(find.byKey(const Key('call-115')), findsOneWidget);
      expect(find.text('Cần đi khám ngay'), findsOneWidget);

      await pump(FakeHealthRepository());
      expect(
        find.text('Chụp huyết áp để nhận đánh giá đầu tiên.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'chưa có hồ sơ: đăng nhập xong bị đưa vào màn thiết lập; có hồ sơ thì vào trang chủ',
    (t) async {
      bigScreen(t);
      for (final withProfile in [false, true]) {
        final auth = FakeAuthRepository();
        final repo = FakeHealthRepository(
          profile: withProfile
              ? const HealthProfile(birthYear: 1950, sex: 'male')
              : null,
        );
        await t.pumpWidget(
          ProviderScope(
            key: ValueKey(withProfile),
            overrides: [
              authRepositoryProvider.overrideWithValue(auth),
              healthRepositoryProvider.overrideWithValue(repo),
            ],
            child: const App(),
          ),
        );
        await settle(t);
        await auth.signIn(email: 'a@b.co', password: 'x');
        await settle(t);
        expect(
          find.byType(HealthSetupScreen),
          withProfile ? findsNothing : findsOneWidget,
        );
        if (withProfile)
          expect(
            find.text('Chào buổi sáng'),
            anyOf(findsOneWidget, findsNothing),
          );
      }
    },
  );
}
