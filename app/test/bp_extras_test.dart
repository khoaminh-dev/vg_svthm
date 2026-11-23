import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/features/bp/domain/bp_models.dart';
import 'package:vg_svthm/features/bp/domain/bp_protocol.dart';
import 'package:vg_svthm/features/bp/domain/bp_repository.dart';
import 'package:vg_svthm/features/bp/presentation/providers/bp_providers.dart';
import 'package:vg_svthm/features/bp/presentation/providers/measure_controller.dart';
import 'package:vg_svthm/features/bp/presentation/screens/measure_screen.dart';
import 'package:vg_svthm/features/health/data/advice_speaker.dart';
import 'package:vg_svthm/features/health/presentation/providers/health_providers.dart';
import 'package:vg_svthm/shared/honorific.dart';

import 'measure_charts_test.dart' show FakeRunner, FakeSpeaker, bigScreen, host;

class _SpeakOn extends SpeakAdviceNotifier {
  @override
  Future<bool> build() async => true;
}

class _Repo implements BpRepository {
  final ctx = <String, List<String>>{};
  @override
  Future<void> add(BpReading r) async {}
  @override
  Future<void> delete(String id) async {}
  @override
  Future<List<BpReading>> list({int limit = 200, String? ownerId}) async => const [];
  @override
  Future<void> markSymptoms(String sessionId, List<String> symptoms) async {}
  @override
  Future<void> markContext(String sessionId, List<String> context) async => ctx[sessionId] = context;
}

List<Override> _ov(_Repo repo) => [
  adviceSpeakerProvider.overrideWithValue(FakeSpeaker()),
  speakAdviceProvider.overrideWith(_SpeakOn.new),
  riskRunnerProvider.overrideWith(() => FakeRunner(null)),
  bpRepositoryProvider.overrideWithValue(repo),
];

void main() {
  setUp(() => setHonorific('bác'));

  group('bpLooksSuspicious (OCR có thể đọc sai)', () {
    test('số bình thường thì không hỏi', () {
      expect(bpLooksSuspicious(128, 82), isFalse);
      expect(bpLooksSuspicious(150, 95), isFalse);
    });
    test('chênh lệch tâm thu/tâm trương quá nhỏ hoặc quá lớn', () {
      expect(bpLooksSuspicious(110, 100), isTrue);
      expect(bpLooksSuspicious(180, 70), isTrue);
    });
    test('rất cao thì hỏi để tránh báo động nhầm vì đọc sai chữ số', () {
      expect(bpLooksSuspicious(190, 110), isTrue);
      expect(bpLooksSuspicious(180, 110), isFalse);
    });
    test('nhảy mạnh so với số trước trong phiên', () {
      const prev = BpSample(130, 80);
      expect(bpLooksSuspicious(175, 85, previous: prev), isTrue);
      expect(bpLooksSuspicious(128, 78, previous: prev), isFalse);
    });
  });

  test('đang đo: 20 phút gần đây mới tính', () {
    final t = DateTime(2026, 11, 23, 8);
    expect(bpIsMeasuring(null, t), isFalse);
    expect(bpIsMeasuring(t.subtract(const Duration(minutes: 5)), t), isTrue);
    expect(bpIsMeasuring(t.subtract(const Duration(minutes: 25)), t), isFalse);
  });

  test('bắt đầu đo thì đặt cờ đang đo; reset thì bỏ cờ (không nhắc khi đang đo)', () {
    final c = ProviderContainer(overrides: _ov(_Repo()));
    addTearDown(c.dispose);
    final n = c.read(measureControllerProvider.notifier);
    n.startFromPrep({});
    expect(c.read(bpMeasuringSinceProvider), isNotNull);
    n.reset();
    expect(c.read(bpMeasuringSinceProvider), isNull);
  });

  test('báo nhịp không đều: ghi bối cảnh vào phiên', () async {
    final repo = _Repo();
    final c = ProviderContainer(overrides: _ov(repo));
    addTearDown(c.dispose);
    final n = c.read(measureControllerProvider.notifier)..startFromPrep({});
    await n.answerIrregular(true);
    expect(c.read(measureControllerProvider).irregular, isTrue);
    expect(repo.ctx.values.single, contains('irregular_pulse'));
  });

  testWidgets('màn xác nhận số: có nút Đúng và Sai, chụp lại', (t) async {
    final repo = _Repo();
    bigScreen(t);
    final r = BpReading(systolic: 190, diastolic: 100, measuredAt: DateTime(2026, 11, 23, 7));
    final c = ProviderContainer(overrides: _ov(repo));
    addTearDown(c.dispose);
    c.read(measureControllerProvider.notifier).startFromPrep({});
    // Dựng bảng xác nhận trực tiếp với trạng thái confirm.
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: MeasureConfirmPanelForTest(m: MeasureState(step: MeasureStep.confirm, reading: r)))),
        ),
      ),
    );
    expect(find.byKey(const Key('bp-confirm')), findsOneWidget);
    expect(find.textContaining('190/100'), findsOneWidget);
    await t.tap(find.byKey(const Key('bp-confirm-no')));
    await t.pump();
    expect(c.read(measureControllerProvider).step, MeasureStep.ready);
  });

  testWidgets('kết quả: hỏi nhịp không đều, trả lời Có thì hiện lời khuyên', (t) async {
    final repo = _Repo();
    final c = ProviderContainer(overrides: _ov(repo));
    addTearDown(c.dispose);
    final n = c.read(measureControllerProvider.notifier)..startFromPrep({});
    bigScreen(t);
    final r = BpReading(systolic: 125, diastolic: 78, measuredAt: DateTime(2026, 11, 23, 7), protocolOk: true);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: MeasureIrregularAskForTest(m: MeasureState(step: MeasureStep.done, reading: r, sessionId: 'sid')))),
        ),
      ),
    );
    expect(find.byKey(const Key('bp-irregular-ask')), findsOneWidget);
    await t.tap(find.byKey(const Key('bp-irregular-yes')));
    await t.pump();
    expect(c.read(measureControllerProvider).irregular, isTrue);
    expect(n, isNotNull);
  });
}
