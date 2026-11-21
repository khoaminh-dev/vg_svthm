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
import 'package:vg_svthm/features/health/presentation/screens/health_history_screen.dart';
import 'package:vg_svthm/features/health/presentation/screens/health_setup_screen.dart';
import 'package:vg_svthm/features/health/presentation/widgets/risk_view.dart';

import 'auth_flow_test.dart' show FakeAuthRepository, settle;

class FakeHealthRepository implements HealthRepository {
  FakeHealthRepository({
    this.profile,
    this.risk,
    List<HealthQa>? qa,
    this.consent,
  }) : qa = qa ?? [];

  HealthProfile? profile;
  RiskResult? risk;
  final List<HealthQa> qa;
  bool? consent;
  final Map<String, RiskFeedback> feedback = {};
  final List<String> feedbackLevels = [];
  int runs = 0;

  @override
  Future<HealthProfile?> getProfile({String? ownerId}) async => profile;

  @override
  Future<void> saveProfile(HealthProfile p) async => profile = p;

  @override
  Future<RiskResult?> latestAssessment({String? ownerId}) async => risk;

  @override
  Future<List<HealthQa>> history() async => List.of(qa);

  @override
  Future<void> clearHistory() async => qa.clear();

  @override
  Future<bool?> getResearchConsent() async => consent;

  @override
  Future<void> setResearchConsent(bool value) async {
    consent = value;
    if (!value) feedback.clear();
  }

  @override
  Future<RiskFeedback?> getFeedback(String assessmentId) async =>
      feedback[assessmentId];

  @override
  Future<void> saveFeedback(
    String assessmentId, {
    required String verdict,
    required String level,
    String? note,
  }) async {
    feedback[assessmentId] = RiskFeedback(verdict: verdict, note: note);
    feedbackLevels.add(level);
  }

  List<TrendPoint> trendPoints = [];

  @override
  Future<List<TrendPoint>> trend({String? ownerId, int limit = 30}) async =>
      trendPoints;

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
  String? id = 'a1',
}) => RiskResult(
  id: id,
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
    expect(r.diabetesP, isNull, reason: 'bản ghi cũ không có tiểu đường');
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

    // Yếu tố hiện sẵn dạng thẻ, không phải gập lại; có thanh 4 nấc và 3 việc nên làm.
    expect(find.byKey(const Key('risk-bar')), findsOneWidget);
    expect(find.text('Hút thuốc'), findsOneWidget);
    expect(find.text('Huyết áp 150/95'), findsOneWidget);
    expect(find.textContaining('trên 70 tuổi'), findsOneWidget);
    expect(find.byKey(const Key('risk-todo')), findsOneWidget);
    expect(find.text('Đo mỗi ngày, cùng giờ'), findsOneWidget);
    // Chỉ phần dấu hiệu nguy hiểm còn gập lại.
    expect(find.text('Đau ngực hoặc khó thở'), findsNothing);
    await t.tap(find.text('Khi nào cần đi khám ngay'));
    await t.pumpAndSettle();
    expect(find.text('Đau ngực hoặc khó thở'), findsOneWidget);
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
  testWidgets(
    'lịch sử hỏi Vy: trống thì có gợi ý, có dữ liệu thì xem và xoá được',
    (t) async {
      bigScreen(t);
      Future<void> open(FakeHealthRepository repo) async {
        await t.pumpWidget(
          ProviderScope(
            overrides: [
              healthRepositoryProvider.overrideWithValue(repo),
              currentUserProvider.overrideWithValue(const AuthUser(id: 'me', username: 'minh', role: AppRole.elder)),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: const HealthHistoryScreen(),
            ),
          ),
        );
        await t.pumpAndSettle();
      }

      await open(FakeHealthRepository());
      expect(find.byKey(const Key('history-empty')), findsOneWidget);
      expect(find.byKey(const Key('history-clear')), findsNothing);

      final repo = FakeHealthRepository(
        qa: [
          HealthQa(
            id: 2,
            question: 'Huyết áp tôi dạo này thế nào',
            answer: 'Tuần này bác đo 4 lần, trung bình 139 trên 89.',
            askedAt: DateTime(2026, 11, 14, 9, 5),
          ),
          HealthQa(
            id: 1,
            question: 'Tôi có nguy hiểm không',
            answer: 'Mức nguy cơ của bác đang thấp.',
            askedAt: DateTime(2026, 11, 13, 20, 30),
          ),
        ],
      );
      await open(repo);
      expect(find.text('Huyết áp tôi dạo này thế nào'), findsOneWidget);
      expect(find.textContaining('trung bình 139 trên 89'), findsOneWidget);
      expect(find.text('09:05 ngày 14/11'), findsOneWidget);
      expect(find.textContaining('tự xoá sau 90 ngày'), findsOneWidget);

      await t.tap(find.byKey(const Key('history-clear')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('history-cancel')));
      await t.pumpAndSettle();
      expect(repo.qa, hasLength(2), reason: 'Giữ lại thì không xoá');

      await t.tap(find.byKey(const Key('history-clear')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('history-confirm')));
      await t.pumpAndSettle();
      expect(repo.qa, isEmpty);
      expect(find.byKey(const Key('history-empty')), findsOneWidget);
    },
  );
  testWidgets(
    'thử nghiệm: dòng bản thử nghiệm, hỏi đồng ý một lần, phản hồi, rút lại',
    (t) async {
      bigScreen(t);
      final repo = FakeHealthRepository(
        risk: result(RiskLevel.high, reasons: ['hypertension']),
      );
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(
              const AuthUser(id: 'u1', username: 'an'),
            ),
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

      // Luôn có dòng "bản thử nghiệm"; chưa đồng ý thì hỏi và chưa có phần phản hồi.
      expect(find.byKey(const Key('trial-strip')), findsOneWidget);
      expect(find.byKey(const Key('research-card')), findsOneWidget);
      expect(find.byKey(const Key('feedback-card')), findsNothing);
      expect(find.byKey(const Key('research-switch')), findsNothing);

      await t.tap(find.byKey(const Key('research-yes')));
      await t.pumpAndSettle();
      expect(repo.consent, isTrue);
      expect(find.byKey(const Key('research-card')), findsNothing);
      await t.scrollUntilVisible(
        find.byKey(const Key('feedback-card')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Kết quả này có đúng với bác không?'), findsOneWidget);

      // Một chạm là lưu, kèm mức nguy cơ lúc đó. Chưa đúng thì có ô ghi chú.
      await t.tap(find.byKey(const Key('fb-wrong')));
      await t.pumpAndSettle();
      expect(repo.feedback['a1']?.verdict, 'wrong');
      expect(repo.feedbackLevels.last, 'high');
      expect(find.byKey(const Key('fb-note')), findsOneWidget);
      await t.enterText(
        find.byKey(const Key('fb-note')),
        'Bác không bị tiểu đường',
      );
      await t.tap(find.byKey(const Key('fb-note-send')));
      await t.pumpAndSettle();
      expect(repo.feedback['a1']?.note, 'Bác không bị tiểu đường');

      // Đổi ý sang "Đúng": không còn ô ghi chú.
      await t.tap(find.byKey(const Key('fb-right')));
      await t.pumpAndSettle();
      expect(repo.feedback['a1']?.verdict, 'right');
      expect(find.byKey(const Key('fb-note')), findsNothing);

      // Rút lại sự đồng ý: xoá phản hồi và ẩn phần phản hồi.
      await t.scrollUntilVisible(
        find.byKey(const Key('research-switch')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.byKey(const Key('research-switch')));
      await t.pumpAndSettle();
      expect(repo.consent, isFalse);
      expect(repo.feedback, isEmpty);
      expect(find.byKey(const Key('feedback-card')), findsNothing);
    },
  );

  testWidgets(
    'đã từ chối nghiên cứu: không hỏi lại và không có phần phản hồi',
    (t) async {
      bigScreen(t);
      final repo = FakeHealthRepository(
        risk: result(RiskLevel.low),
        consent: false,
      );
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(
              const AuthUser(id: 'u1', username: 'an'),
            ),
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
      expect(find.byKey(const Key('research-card')), findsNothing);
      expect(find.byKey(const Key('feedback-card')), findsNothing);
      expect(find.byKey(const Key('trial-strip')), findsOneWidget);
    },
  );
  test(
    'RiskResult và HealthProfile đọc được phần tiểu đường, chiều cao, cân nặng',
    () {
      final r = RiskResult.fromJson({
        'level': 'high',
        'reasons': <String>[],
        'bp': {
          'systolic': 130,
          'diastolic': 80,
          'measuredAt': '2026-11-14T01:10:00Z',
        },
        'diabetes': {'p': 0.31, 'level': 'high', 'bmi': 29.4},
        'createdAt': '2026-11-14T01:11:00Z',
      });
      expect(r.diabetesP, closeTo(0.31, 1e-9));
      expect(r.diabetesLevel, RiskLevel.high);

      final p = HealthProfile.fromMap({
        'birth_year': 1955,
        'sex': 'male',
        'high_cholesterol': true,
        'difficulty_walking': false,
        'height_cm': 165,
        'weight_kg': 70,
      });
      expect(p.hasBody, isTrue);
      expect(p.highCholesterol, isTrue);
      expect(p.toUpsert()['height_cm'], 165);
      expect(
        const HealthProfile(birthYear: 1950, sex: 'male').hasBody,
        isFalse,
      );
    },
  );

  testWidgets(
    'thiết lập: chiều cao, cân nặng không bắt buộc; nhập sai thì báo, nhập đúng thì lưu',
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
      await t.tap(find.byKey(const Key('sex-male')));
      await t.pump();

      await t.enterText(find.byKey(const Key('height-field')), '30');
      await t.tap(find.byKey(const Key('health-next')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('body-error')), findsOneWidget);
      expect(find.text('Bước 1/2'), findsOneWidget);

      await t.enterText(find.byKey(const Key('height-field')), '165');
      await t.enterText(find.byKey(const Key('weight-field')), '70');
      await t.pump();
      expect(find.byKey(const Key('body-error')), findsNothing);
      await t.tap(find.byKey(const Key('health-next')));
      await t.pumpAndSettle();
      expect(find.text('Khó đi bộ hoặc leo cầu thang'), findsOneWidget);
      expect(find.text('Mỡ máu cao'), findsOneWidget);
      await t.tap(find.byKey(const Key('highChol-yes')));
      await t.tap(find.byKey(const Key('health-next')));
      await t.pumpAndSettle();

      final p = repo.profile!;
      expect(p.heightCm, 165);
      expect(p.weightKg, 70);
      expect(p.highCholesterol, isTrue);
      expect(p.difficultyWalking, isFalse);
    },
  );

  testWidgets(
    'tab Đánh giá: chưa có chiều cao/cân nặng thì mời bổ sung; đã có số đo hoặc đã bị tiểu đường thì không mời',
    (t) async {
      bigScreen(t);
      Future<void> open(FakeHealthRepository repo) async {
        await t.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              currentUserProvider.overrideWithValue(
                const AuthUser(id: 'u1', username: 'an'),
              ),
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
      }

      const noBody = HealthProfile(birthYear: 1955, sex: 'male');
      await open(
        FakeHealthRepository(
          profile: noBody,
          risk: result(RiskLevel.attention),
        ),
      );
      expect(find.byKey(const Key('body-prompt')), findsOneWidget);

      await open(
        FakeHealthRepository(
          profile: const HealthProfile(
            birthYear: 1955,
            sex: 'male',
            heightCm: 160,
            weightKg: 60,
          ),
          risk: result(RiskLevel.attention),
        ),
      );
      expect(
        find.byKey(const Key('body-prompt')),
        findsNothing,
        reason: 'đã có chiều cao, cân nặng thì không mời nữa',
      );

      await open(
        FakeHealthRepository(
          profile: const HealthProfile(
            birthYear: 1955,
            sex: 'male',
            diabetes: true,
          ),
          risk: result(RiskLevel.attention),
        ),
      );
      expect(
        find.byKey(const Key('body-prompt')),
        findsNothing,
        reason: 'đã bị tiểu đường thì không cần dự đoán',
      );
    },
  );
  testWidgets('tab Đánh giá: cột mức huyết áp và biểu đồ xu hướng', (t) async {
    bigScreen(t);
    Future<void> open(List<TrendPoint> pts) async {
      final repo = FakeHealthRepository(risk: result(RiskLevel.attention))
        ..trendPoints = pts;
      await t.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            currentUserProvider.overrideWithValue(
              const AuthUser(id: 'u1', username: 'an'),
            ),
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
    }

    await open([]);
    expect(find.byKey(const Key('assessment-bp')), findsOneWidget);
    expect(find.byKey(const Key('bp-bars')), findsOneWidget);
    expect(find.text('Mức huyết áp (150/95)'), findsOneWidget);
    expect(find.text('Tăng huyết áp độ 2'), findsOneWidget);
    await t.scrollUntilVisible(
      find.byKey(const Key('trend-empty')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('trend-empty')), findsOneWidget);

    await open([
      TrendPoint(at: DateTime(2026, 11, 10), stroke: 0.08, heart: 0.20),
      TrendPoint(
        at: DateTime(2026, 11, 12),
        stroke: 0.10,
        heart: 0.24,
        diabetes: 0.12,
      ),
      TrendPoint(
        at: DateTime(2026, 11, 14),
        stroke: 0.12,
        heart: 0.25,
        diabetes: 0.15,
      ),
    ]);
    await t.scrollUntilVisible(
      find.byKey(const Key('trend-chart')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('trend-chart')), findsOneWidget);
    expect(find.text('Tiểu đường'), findsWidgets);
    expect(find.text('10/11'), findsOneWidget);
    expect(find.text('14/11'), findsOneWidget);
  });

  test('TrendPoint đọc cả cột xác suất lẫn cột details', () {
    final p = TrendPoint.fromRow({
      'created_at': '2026-11-14T01:00:00Z',
      'stroke_p': 0.1,
      'heart_p': 0.2,
      'details': {
        'diabetes': {'p': 0.3},
      },
    });
    expect(p.stroke, 0.1);
    expect(p.heart, 0.2);
    expect(p.diabetes, 0.3);
    final old = TrendPoint.fromRow({
      'created_at': '2026-11-01T01:00:00Z',
      'details': {},
    });
    expect(old.diabetes, isNull);
  });
}
