import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:vg_svthm/core/theme/app_theme.dart';
import 'package:vg_svthm/features/bp/domain/bp_models.dart';
import 'package:vg_svthm/features/bp/presentation/providers/measure_controller.dart';
import 'package:vg_svthm/features/bp/presentation/screens/measure_screen.dart';
import 'package:vg_svthm/features/health/data/advice_speaker.dart';
import 'package:vg_svthm/features/health/domain/health_models.dart';
import 'package:vg_svthm/features/health/presentation/providers/health_providers.dart';
import 'package:vg_svthm/features/health/presentation/risk_texts.dart';
import 'package:vg_svthm/features/health/presentation/widgets/risk_charts.dart';

class FakeSpeaker extends AdviceSpeaker {
  final said = <String>[];
  final replaced = <String>[];
  int stops = 0;

  @override
  Future<void> say(String text) async => said.add(text);

  @override
  Future<void> replace(String text) async => replaced.add(text);

  @override
  Future<void> stop() async => stops++;
}

class FakeRunner extends RiskRunner {
  FakeRunner(this.value);
  final RiskResult? value;

  @override
  AsyncValue<RiskResult?> build() => AsyncData(value);
}

RiskResult risk({
  RiskLevel level = RiskLevel.high,
  double? stroke = 0.12,
  RiskLevel strokeLevel = RiskLevel.high,
  double? heart = 0.25,
  RiskLevel heartLevel = RiskLevel.attention,
  List<String> reasons = const ['hypertension'],
  bool oldAge = false,
}) => RiskResult(
  level: level,
  reasons: reasons,
  systolic: 150,
  diastolic: 95,
  measuredAt: DateTime(2026, 11, 15, 8),
  createdAt: DateTime(2026, 11, 15, 8, 1),
  strokeP: stroke,
  strokeLevel: strokeLevel,
  heartP: heart,
  heartLevel: heartLevel,
  ageOutOfRange: oldAge,
);

void bigScreen(WidgetTester t) {
  t.view.physicalSize = const Size(900, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Widget host(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      key: UniqueKey(),
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

int litBars(WidgetTester t) => t
    .widgetList(
      find.byWidgetPredicate((w) {
        final k = w.key;
        return k is ValueKey<String> &&
            k.value.startsWith('bar-') &&
            k.value.endsWith('-on');
      }),
    )
    .length;

void main() {
  test('RiskDonut.percent: làm tròn, dưới 1% không nói là 0', () {
    expect(RiskDonut.percent(0.123), '12%');
    expect(RiskDonut.percent(0.004), '<1%');
    expect(RiskDonut.percent(0), '0%');
    expect(RiskDonut.percent(0.9993), '>99%');
    expect(RiskDonut.percent(0.5), '50%');
  });

  test(
    'riskSpokenDetailed: nêu tên vấn đề ở mức đáng chú ý, không đọc số %',
    () {
      final s = riskSpokenDetailed(risk());
      expect(s, contains('Nguy cơ đột quỵ ở mức cao.'));
      expect(s, contains('Nguy cơ tim mạch ở mức cần chú ý.'));
      expect(s, contains('đi khám sớm'));
      expect(s, isNot(contains('%')));
      expect(s, isNot(contains('12')));
      final only = riskSpokenDetailed(risk(heartLevel: RiskLevel.low));
      expect(only, contains('đột quỵ'));
      expect(only, isNot(contains('tim mạch ở mức')));
      final urgent = riskSpokenDetailed(risk(level: RiskLevel.urgent));
      expect(urgent, contains('115'));
      expect(urgent, isNot(contains('Nguy cơ đột quỵ')));
    },
  );

  testWidgets('BpBars: số cột sáng tăng theo mức huyết áp', (t) async {
    for (final c in BpCategory.values) {
      await t.pumpWidget(host(BpBars(category: c)));
      await t.pumpAndSettle();
      expect(litBars(t), c.index + 1, reason: c.label);
      expect(find.byKey(const Key('bp-bars')), findsOneWidget);
    }
  });

  testWidgets('BpBars: các cột mọc dần, cột cao mọc sau cùng', (t) async {
    await t.pumpWidget(host(const BpBars(category: BpCategory.stage2)));
    await t.pump(const Duration(milliseconds: 80));
    final earlyLast = t.getSize(find.byKey(const Key('bar-3-on'))).height;
    await t.pumpAndSettle();
    final lateLast = t.getSize(find.byKey(const Key('bar-3-on'))).height;
    expect(earlyLast, lessThan(lateLast));
  });

  testWidgets(
    'RiskDonuts: tên vấn đề, nhãn thời gian và % đúng; trên 70 tuổi có dấu *',
    (t) async {
      await t.pumpWidget(host(RiskDonuts(result: risk())));
      await t.pumpAndSettle();
      expect(find.text('Đột quỵ'), findsOneWidget);
      expect(find.text('ước tính'), findsOneWidget);
      expect(find.text('Tim mạch'), findsOneWidget);
      expect(find.text('trong 10 năm'), findsOneWidget);
      expect(find.text('12%'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);

      await t.pumpWidget(host(RiskDonuts(result: risk(oldAge: true))));
      await t.pumpAndSettle();
      expect(find.text('Tim mạch *'), findsOneWidget);
    },
  );

  testWidgets(
    'Bảng kết quả đo: số đo + cột, lời khuyên không in chữ mà do máy đọc',
    (t) async {
      bigScreen(t);
      final speaker = FakeSpeaker();
      final reading = BpReading(
        systolic: 150,
        diastolic: 95,
        pulse: 72,
        measuredAt: DateTime(2026, 11, 15, 8),
      );
      await t.pumpWidget(
        host(
          MeasureResultPanel(
            m: MeasureState(
              step: MeasureStep.done,
              reading: reading,
              advice: 'Huyết áp cao. Bác nên nghỉ ngơi.',
            ),
          ),
          overrides: [
            adviceSpeakerProvider.overrideWithValue(speaker),
            riskRunnerProvider.overrideWith(() => FakeRunner(risk())),
          ],
        ),
      );
      await t.pumpAndSettle();

      expect(find.text('150/95'), findsOneWidget);
      expect(find.text('Mạch 72'), findsOneWidget);
      expect(find.byKey(const Key('bp-bars')), findsOneWidget);
      expect(find.text('Mức huyết áp'), findsOneWidget);
      expect(litBars(t), BpCategory.of(150, 95).index + 1);
      expect(find.text('Huyết áp cao. Bác nên nghỉ ngơi.'), findsNothing);
      expect(find.byKey(const Key('advice-text')), findsNothing);

      expect(find.byKey(const Key('measure-risk')), findsOneWidget);
      expect(find.text('12%'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
      expect(find.byKey(const Key('risk-tag-hypertension')), findsOneWidget);

      await t.tap(find.byKey(const Key('advice-replay')));
      await t.pump();
      expect(speaker.replaced, hasLength(1));
      expect(
        speaker.replaced.single,
        contains('Huyết áp cao. Bác nên nghỉ ngơi.'),
      );
      expect(speaker.replaced.single, contains('Nguy cơ đột quỵ ở mức cao.'));
      expect(speaker.replaced.single, isNot(contains('%')));

      await t.tap(find.byKey(const Key('advice-show')));
      await t.pump();
      expect(find.byKey(const Key('advice-text')), findsOneWidget);
      expect(
        find.textContaining('Huyết áp cao. Bác nên nghỉ ngơi.'),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('advice-show')));
      await t.pump();
      expect(find.byKey(const Key('advice-text')), findsNothing);
    },
  );

  testWidgets(
    'Bảng kết quả đo: nguy cơ thấp không có khung; khẩn cấp có Gọi 115',
    (t) async {
      bigScreen(t);
      final reading = BpReading(
        systolic: 118,
        diastolic: 78,
        measuredAt: DateTime(2026, 11, 15),
      );
      Future<void> open(RiskResult? r) async {
        await t.pumpWidget(
          host(
            MeasureResultPanel(
              m: MeasureState(
                step: MeasureStep.done,
                reading: reading,
                advice: 'Huyết áp bình thường.',
              ),
            ),
            overrides: [
              adviceSpeakerProvider.overrideWithValue(FakeSpeaker()),
              riskRunnerProvider.overrideWith(() => FakeRunner(r)),
            ],
          ),
        );
        await t.pumpAndSettle();
      }

      await open(
        risk(
          level: RiskLevel.low,
          strokeLevel: RiskLevel.low,
          heartLevel: RiskLevel.low,
        ),
      );
      expect(find.byKey(const Key('measure-risk')), findsNothing);
      expect(litBars(t), 1);

      await open(risk(level: RiskLevel.urgent));
      expect(find.byKey(const Key('measure-risk')), findsOneWidget);
      expect(find.text('Gọi 115'), findsOneWidget);
    },
  );

  test('Công tắc đọc lời khuyên: mặc định bật khi chưa có cài đặt', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(speakAdviceProvider.future), isTrue);
  });
}
