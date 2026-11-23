import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/features/auth/domain/auth_user.dart';
import 'package:vg_svthm/features/auth/presentation/providers/auth_providers.dart';
import 'package:vg_svthm/features/bp/domain/bp_advice.dart';
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
  final marked = <String, List<String>>{};
  @override
  Future<void> add(BpReading r) async {}
  @override
  Future<void> delete(String id) async {}
  @override
  Future<List<BpReading>> list({int limit = 200, String? ownerId}) async => const [];
  @override
  Future<void> markSymptoms(String sessionId, List<String> symptoms) async => marked[sessionId] = symptoms;
}

BpReading _r(int s, int d, {bool? ok}) =>
    BpReading(systolic: s, diastolic: d, measuredAt: DateTime(2026, 11, 23, 7), protocolOk: ok);

MeasureState _done(List<BpSample> samples, {Set<BpContext> ctx = const {}, bool? symptoms}) {
  final d = bpDecide(samples, context: ctx, symptoms: symptoms);
  final last = samples.last;
  final r = _r(last.sys, last.dia, ok: last.rested);
  return MeasureState(
    step: MeasureStep.done,
    reading: r,
    advice: bpAdvice(r, decision: d),
    samples: samples,
    contexts: ctx,
    decision: d,
    sessionId: 'sid-1',
    symptoms: symptoms,
  );
}

List<Override> _ov({FakeSpeaker? speaker, _Repo? repo}) => [
  adviceSpeakerProvider.overrideWithValue(speaker ?? FakeSpeaker()),
  speakAdviceProvider.overrideWith(_SpeakOn.new),
  riskRunnerProvider.overrideWith(() => FakeRunner(null)),
  if (repo != null) bpRepositoryProvider.overrideWithValue(repo),
];

Future<void> _panel(WidgetTester t, MeasureState m, {List<Override>? ov}) async {
  bigScreen(t);
  await t.pumpWidget(host(MeasureResultPanel(m: m), overrides: ov ?? _ov()));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => setHonorific('bác'));

  group('lời khuyên một lần đo (bpAdvice) theo AHA', () {
    test('mọi mức từ hơi cao trở lên: ngồi yên, không bao giờ khuyên đi lại/vận động', () {
      for (final (s, d) in [(125, 78), (135, 85), (150, 95), (190, 110)]) {
        final a = bpAdvice(_r(s, d));
        expect(a, contains('ngồi yên'), reason: '$s/$d');
        expect(a, isNot(contains('đi vòng')));
        expect(a, isNot(contains('đi bộ')));
        expect(a, isNot(contains('vận động')));
      }
      expect(bpAdvice(_r(150, 95)), contains('5 phút'));
      expect(bpAdvice(_r(190, 110)), allOf(contains('1 phút'), contains('115')));
    });
    test('bình thường chỉ khen, không bắt đo lại', () {
      final a = bpAdvice(_r(110, 70));
      expect(a, contains('bình thường'));
      expect(a, isNot(contains('đo lại')));
    });
    test('xưng hô theo người dùng', () {
      setHonorific('cô');
      expect(bpAdvice(_r(150, 95)), startsWith('Số này hơi cao'));
      expect(bpAdvice(_r(150, 95)), contains('Cô ngồi yên'));
    });
  });

  group('controller: phiên đo', () {
    ProviderContainer make({_Repo? repo}) {
      final c = ProviderContainer(overrides: _ov(repo: repo));
      addTearDown(c.dispose);
      return c;
    }

    test('mặc định ở bước chuẩn bị', () {
      expect(make().read(measureControllerProvider).step, MeasureStep.prep);
    });

    test('"Đã nghỉ yên rồi": vào camera luôn, số đo sau là đủ chuẩn', () {
      final c = make();
      final n = c.read(measureControllerProvider.notifier)..startFromPrep({});
      final s = c.read(measureControllerProvider);
      expect(s.step, MeasureStep.ready);
      expect(s.rested, isTrue);
      expect(s.sessionId, isNotNull);
      expect(n, isNotNull);
    });

    test('vừa ngủ dậy: phải nghỉ 5 phút; hết giờ thì đủ chuẩn', () {
      final c = make();
      final n = c.read(measureControllerProvider.notifier)..startFromPrep({BpContext.wokeUp});
      var s = c.read(measureControllerProvider);
      expect(s.step, MeasureStep.resting);
      expect(s.restTotal, bpRestSeconds);
      expect(s.rested, isFalse);
      n.finishRest();
      s = c.read(measureControllerProvider);
      expect(s.step, MeasureStep.ready);
      expect(s.rested, isTrue);
      expect(s.contexts, {BpContext.wokeUp});
    });

    test('cà phê/thuốc lá: chờ 30 phút', () {
      final c = make();
      c.read(measureControllerProvider.notifier).startFromPrep({BpContext.caffeineSmoke});
      expect(c.read(measureControllerProvider).restTotal, bpCaffeineWaitSeconds);
    });

    test('bỏ qua nghỉ: vẫn đo được nhưng bị đánh dấu chưa chuẩn', () {
      final c = make();
      final n = c.read(measureControllerProvider.notifier)..startFromPrep({BpContext.exertion});
      n.skipRest();
      final s = c.read(measureControllerProvider);
      expect(s.step, MeasureStep.ready);
      expect(s.rested, isFalse);
    });

    test('chờ 1 phút giữa hai số: số hai đủ chuẩn nếu số đầu đã đủ chuẩn', () {
      final c = make();
      final n = c.read(measureControllerProvider.notifier)..startFromPrep({});
      // giả lập đã có 1 số đủ chuẩn trong phiên
      c.read(measureControllerProvider.notifier).state = c
          .read(measureControllerProvider)
          .copyWith(samples: [const BpSample(140, 90, rested: true)]);
      n.startRest(bpBetweenReadingsSeconds);
      n.finishRest();
      expect(c.read(measureControllerProvider).rested, isTrue);
    });

    test('chờ 1 phút sau số rất cao chưa nghỉ: số hai vẫn chưa chuẩn', () {
      final c = make();
      final n = c.read(measureControllerProvider.notifier)..startFromPrep({BpContext.exertion});
      n.skipRest();
      c.read(measureControllerProvider.notifier).state = c
          .read(measureControllerProvider)
          .copyWith(samples: [const BpSample(190, 110)]);
      n.startRest(bpBetweenReadingsSeconds);
      n.finishRest();
      expect(c.read(measureControllerProvider).rested, isFalse);
    });

    test('trả lời triệu chứng: ghi vào phiên, đổi quyết định', () async {
      final repo = _Repo();
      final c = make(repo: repo);
      final n = c.read(measureControllerProvider.notifier);
      n.state = _done([const BpSample(190, 110, rested: true), const BpSample(186, 108, rested: true)]);
      expect(c.read(measureControllerProvider).decision!.action, BpAction.askSymptoms);
      await n.answerSymptoms({'chest_pain'});
      expect(c.read(measureControllerProvider).decision!.action, BpAction.call115);
      expect(repo.marked['sid-1'], ['chest_pain']);
      n.state = _done([const BpSample(190, 110, rested: true), const BpSample(186, 108, rested: true)]);
      await n.answerSymptoms({});
      expect(c.read(measureControllerProvider).decision!.action, BpAction.callDoctorNow);
      expect(repo.marked['sid-1'], ['none']);
    });

    test('retakePhoto giữ phiên; reset về chuẩn bị', () {
      final c = make();
      final n = c.read(measureControllerProvider.notifier);
      n.state = _done([const BpSample(150, 95, rested: true)]);
      n.retakePhoto();
      var s = c.read(measureControllerProvider);
      expect(s.step, MeasureStep.ready);
      expect(s.samples, hasLength(1));
      expect(s.rested, isFalse); // đã dùng hết lần nghỉ cho số trước; muốn đo tiếp phải nghỉ lại hoặc theo thẻ việc cần làm
      n.reset();
      s = c.read(measureControllerProvider);
      expect(s.step, MeasureStep.prep);
      expect(s.samples, isEmpty);
    });
  });

  group('giao diện', () {
    testWidgets('màn đo mở bằng bước chuẩn bị, không vào camera ngay', (t) async {
      bigScreen(t);
      await t.pumpWidget(ProviderScope(
        overrides: _ov(),
        child: const MaterialApp(home: MeasureScreen()),
      ));
      await t.pump();
      expect(find.byKey(const Key('bp-prep')), findsOneWidget);
      expect(find.text('Chuẩn bị đo'), findsOneWidget);
      expect(find.textContaining('Ngồi thẳng, lưng tựa ghế'), findsOneWidget);
      expect(find.textContaining('Bác vừa làm gì?'), findsOneWidget);
      expect(find.byKey(const Key('measure-shutter')), findsNothing);
    });

    testWidgets('chọn "Vừa ngủ dậy": đếm ngược 5 phút; bỏ qua thì vào camera', (t) async {
      bigScreen(t);
      final container = ProviderContainer(overrides: _ov());
      addTearDown(container.dispose);
      var now = DateTime(2026, 11, 23, 7);
      container.read(measureControllerProvider.notifier).clock = () => now;
      await t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MeasureScreen()),
      ));
      await t.pump();
      await t.tap(find.byKey(const Key('bp-ctx-woke')));
      await t.pump();
      expect(find.byKey(const Key('bp-rest')), findsOneWidget);
      expect(find.text('05:00'), findsOneWidget);
      expect(find.textContaining('đừng đi lại'), findsOneWidget);
      now = now.add(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('04:57'), findsOneWidget);
      await t.tap(find.byKey(const Key('bp-rest-skip')));
      await t.pump();
      expect(find.byKey(const Key('bp-rest')), findsNothing);
      expect(find.byKey(const Key('bp-prep')), findsNothing);
    });

    testWidgets('hết giờ nghỉ tự chuyển sang bước đo', (t) async {
      bigScreen(t);
      final container = ProviderContainer(overrides: _ov());
      addTearDown(container.dispose);
      await t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MeasureScreen()),
      ));
      await t.pump();
      final n = container.read(measureControllerProvider.notifier);
      var now = DateTime(2026, 11, 23, 7);
      n.clock = () => now;
      n.startFromPrep({BpContext.exertion});
      await t.pump();
      expect(find.text('05:00'), findsOneWidget);
      now = now.add(const Duration(minutes: 5));
      await t.pump(const Duration(seconds: 1));
      expect(container.read(measureControllerProvider).step, MeasureStep.ready);
      expect(container.read(measureControllerProvider).rested, isTrue);
    });

    testWidgets('số cao đơn lẻ chưa chuẩn: nhãn "Số đo cao", không gắn "Tăng huyết áp độ 2"; nút ngồi nghỉ 5 phút', (t) async {
      await _panel(t, _done([const BpSample(150, 95)], ctx: {BpContext.wokeUp}));
      expect(find.text('Số đo cao'), findsOneWidget);
      expect(find.textContaining('Tăng huyết áp'), findsNothing);
      expect(find.byKey(const Key('bp-action')), findsOneWidget);
      expect(find.text('Ngồi yên 5 phút, rồi đo lại'), findsOneWidget);
      expect(find.byKey(const Key('bp-start-rest')), findsOneWidget);
      expect(find.byKey(const Key('bp-call-115')), findsNothing);
    });

    testWidgets('bình thường: không có thẻ việc cần làm nếu đã đủ chuẩn', (t) async {
      await _panel(t, _done([const BpSample(112, 72, rested: true)]));
      expect(find.byKey(const Key('bp-action')), findsNothing);
      expect(find.text('Bình thường'), findsWidgets);
    });

    testWidgets('bình thường nhưng mới 1 số chưa chuẩn: mời đo thêm 1 số', (t) async {
      await _panel(t, _done([const BpSample(112, 72)]));
      expect(find.text('Mới đo 1 lần, chưa chuẩn'), findsOneWidget);
      expect(find.byKey(const Key('bp-add-reading')), findsOneWidget);
    });

    testWidgets('hai số: hiện Số 1, Số 2 và Trung bình; nhãn theo trung bình', (t) async {
      await _panel(t, _done([const BpSample(150, 95, rested: true), const BpSample(148, 94, rested: true)]));
      expect(find.byKey(const Key('bp-session')), findsOneWidget);
      expect(find.text('Số 1'), findsOneWidget);
      expect(find.text('150/95'), findsWidgets);
      expect(find.text('Trung bình'), findsOneWidget);
      expect(find.text('149/95'), findsOneWidget);
      expect(find.text('Báo người thân hoặc bác sĩ trong hôm nay'), findsOneWidget);
    });

    testWidgets('rất cao lần 1: chờ 1 phút + nút Gọi 115 luôn hiện', (t) async {
      await _panel(t, _done([const BpSample(190, 110)]));
      expect(find.text('Rất cao'), findsOneWidget);
      expect(find.byKey(const Key('bp-start-wait')), findsOneWidget);
      expect(find.byKey(const Key('bp-call-115')), findsOneWidget);
    });

    testWidgets('rất cao lần 2: hỏi triệu chứng; "Có" chỉ bấm được khi chọn ô', (t) async {
      final repo = _Repo();
      bigScreen(t);
      final container = ProviderContainer(overrides: [
        ..._ov(repo: repo),
        currentUserProvider.overrideWithValue(const AuthUser(id: 'me', username: 'minh', role: AppRole.family)),
      ]);
      addTearDown(container.dispose);
      container.read(measureControllerProvider.notifier).state =
          _done([const BpSample(190, 110, rested: true), const BpSample(186, 108, rested: true)]);
      await t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(builder: (_, ref, _) => MeasureResultPanel(m: ref.watch(measureControllerProvider))),
          ),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text('Bác có triệu chứng nào không?'), findsOneWidget);
      final yes = find.byKey(const Key('bp-symptom-yes'));
      expect(t.widget<FilledButton>(yes).onPressed, isNull);
      await t.tap(find.byKey(const Key('bp-sym-chest_pain')));
      await t.pump();
      expect(t.widget<FilledButton>(yes).onPressed, isNotNull);
      await t.ensureVisible(yes);
      await t.tap(yes);
      await t.pumpAndSettle();
      expect(find.text('Gọi 115 ngay, đừng chờ'), findsOneWidget);
      expect(repo.marked['sid-1'], ['chest_pain']);
    });

    testWidgets('máy nhỏ: bảng kết quả dài vẫn cuộn được, không tràn', (t) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(host(
        MeasureResultPanel(m: _done([const BpSample(190, 110, rested: true), const BpSample(186, 108, rested: true)])),
        overrides: _ov(),
      ));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });
}
