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
  Future<HealthProfile?> getProfile() async => profile;

  @override
  Future<void> saveProfile(HealthProfile p) async => profile = p;

  @override
  Future<RiskResult?> latestAssessment() async => risk;

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
            overrides: [healthRepositoryProvider.overrideWithValue(repo)],
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
}
