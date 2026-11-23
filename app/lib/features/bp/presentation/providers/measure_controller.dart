import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/analytics/analytics.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../shared/honorific.dart';
import '../../../health/data/advice_speaker.dart';
import '../../../health/presentation/providers/health_providers.dart';
import '../../../health/presentation/risk_texts.dart';
import '../../../ocr/domain/ocr_models.dart';
import '../../../ocr/presentation/providers/ocr_controller.dart';
import '../../../ocr/presentation/providers/ocr_providers.dart';
import '../../domain/bp_advice.dart';
import '../../domain/bp_models.dart';
import '../../domain/bp_protocol.dart';
import 'bp_providers.dart';

/// prep: chuẩn bị + hỏi bối cảnh · resting: đếm ngược ngồi nghỉ · ready: camera · analyzing/done/failed như trước.
/// confirm: số đọc có vẻ lạ, hỏi người dùng "đúng không?" trước khi lưu và đưa lời khuyên.
enum MeasureStep { prep, resting, ready, analyzing, confirm, done, failed }

/// Lúc bắt đầu một phiên đo (null = không đo). Để không nhắc đo khi người dùng đang đo.
class BpMeasuringSince extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;
  void set(DateTime? t) => state = t;
}

final bpMeasuringSinceProvider = NotifierProvider<BpMeasuringSince, DateTime?>(
  BpMeasuringSince.new,
);

/// Đang đo trong 20 phút gần đây thì coi là đang đo.
bool bpIsMeasuring(DateTime? since, DateTime now) =>
    since != null && now.difference(since).inMinutes < 20;

/// Ngồi nghỉ yên 5 phút trước khi đo (AHA); vừa uống cà phê/hút thuốc thì chờ 30 phút.
const bpRestSeconds = 300;
const bpCaffeineWaitSeconds = 1800;
const bpBetweenReadingsSeconds = 60;

/// Triệu chứng nguy hiểm khi huyết áp rất cao (AHA). Mã lưu vào DB.
const bpSymptomLabels = <String, String>{
  'chest_pain': 'Đau ngực',
  'short_breath': 'Khó thở',
  'numb_weak': 'Tê, yếu hoặc méo miệng',
  'speech_vision': 'Nói khó hoặc nhìn mờ',
};

class MeasureState {
  const MeasureState({
    this.step = MeasureStep.prep,
    this.imagePath,
    this.reading,
    this.advice,
    this.error,
    this.saving = false,
    this.samples = const [],
    this.contexts = const {},
    this.decision,
    this.rested = false,
    this.restTotal = 0,
    this.restEndsAt,
    this.sessionId,
    this.symptoms,
    this.irregular,
  });

  final MeasureStep step;
  final String? imagePath;
  final BpReading? reading;
  final String? advice;
  final String? error;

  /// Đã có kết quả nhưng đang lưu ngầm.
  final bool saving;

  /// Các số đo trong phiên này (tối đa 3), theo thứ tự.
  final List<BpSample> samples;

  /// Bối cảnh trước số đo đầu tiên (rỗng = đã nghỉ yên).
  final Set<BpContext> contexts;
  final BpDecision? decision;

  /// Số đo sắp tới có được ngồi nghỉ đủ chuẩn không.
  final bool rested;
  final int restTotal;
  final DateTime? restEndsAt;
  final String? sessionId;

  /// Người dùng báo có triệu chứng nguy hiểm (null = chưa hỏi).
  final bool? symptoms;

  /// Máy báo nhịp tim không đều (null = chưa hỏi).
  final bool? irregular;

  MeasureState copyWith({
    MeasureStep? step,
    String? imagePath,
    BpReading? reading,
    String? advice,
    String? error,
    bool? saving,
    List<BpSample>? samples,
    Set<BpContext>? contexts,
    BpDecision? decision,
    bool? rested,
    int? restTotal,
    DateTime? restEndsAt,
    bool? symptoms,
    bool? irregular,
  }) => MeasureState(
    step: step ?? this.step,
    imagePath: imagePath ?? this.imagePath,
    reading: reading ?? this.reading,
    advice: advice ?? this.advice,
    error: error ?? this.error,
    saving: saving ?? this.saving,
    samples: samples ?? this.samples,
    contexts: contexts ?? this.contexts,
    decision: decision ?? this.decision,
    rested: rested ?? this.rested,
    restTotal: restTotal ?? this.restTotal,
    restEndsAt: restEndsAt ?? this.restEndsAt,
    sessionId: sessionId,
    symptoms: symptoms ?? this.symptoms,
    irregular: irregular ?? this.irregular,
  );
}

String _newSessionId() {
  // UUID v4 cho khoá phiên.
  final rnd = Random.secure();
  final b = List<int>.generate(16, (_) => rnd.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Một phiên đo: chuẩn bị → ngồi nghỉ 5 phút → đo → (nếu cao) chờ 1 phút đo lại → trung bình → việc cần làm.
class MeasureController extends Notifier<MeasureState> {
  @override
  MeasureState build() => const MeasureState();

  DateTime Function() clock = DateTime.now;
  DateTime? _restStartedAt;

  void reset() {
    unawaited(ref.read(adviceSpeakerProvider).stop());
    _restStartedAt = null;
    _pending = null;
    ref.read(bpMeasuringSinceProvider.notifier).set(null);
    state = const MeasureState();
  }

  /// Từ màn chuẩn bị: [contexts] rỗng nghĩa là "đã nghỉ yên rồi" → vào camera luôn.
  void startFromPrep(Set<BpContext> contexts) {
    final sid = state.sessionId ?? _newSessionId();
    Analytics.track('bp_prep_view', {
      'ctx': contexts.map((c) => c.name).join(','),
    });
    ref.read(bpMeasuringSinceProvider.notifier).set(clock());
    state = MeasureState(
      step: contexts.isEmpty ? MeasureStep.ready : MeasureStep.prep,
      contexts: contexts,
      rested: contexts.isEmpty,
      sessionId: sid,
    );
    if (contexts.isNotEmpty) {
      startRest(
        contexts.contains(BpContext.caffeineSmoke)
            ? bpCaffeineWaitSeconds
            : bpRestSeconds,
      );
    }
  }

  /// Vào màn đo là đếm ngược ngồi nghỉ 5 phút ngay (không hỏi trước): người dùng chỉ cần chạm
  /// "Đã ngồi nghỉ rồi" nếu thật sự đã nghỉ, hoặc "Vừa làm việc khác" nếu cần chọn bối cảnh.
  void beginRest() {
    final sid = state.sessionId ?? _newSessionId();
    Analytics.track('bp_prep_view', {'ctx': 'auto_rest'});
    ref.read(bpMeasuringSinceProvider.notifier).set(clock());
    state = MeasureState(sessionId: sid);
    startRest(bpRestSeconds);
  }

  /// Người dùng cho biết đã ngồi nghỉ yên đủ: vào camera luôn, số đo tới tính là đủ chuẩn.
  void confirmRested() {
    Analytics.track('bp_rest_confirmed');
    state = MeasureState(
      step: MeasureStep.ready,
      samples: state.samples,
      contexts: const {},
      rested: true,
      restTotal: bpRestSeconds,
      sessionId: state.sessionId,
      symptoms: state.symptoms,
    );
  }

  /// "Vừa làm việc khác": quay lại bước chọn bối cảnh (ngủ dậy, đi lại, cà phê/thuốc lá).
  void backToPrep() {
    Analytics.track('bp_back_to_prep');
    state = MeasureState(sessionId: state.sessionId, samples: state.samples);
  }

  /// Bắt đầu đếm ngược ngồi yên [seconds] giây rồi mới cho đo.
  void startRest(int seconds) {
    _restStartedAt = clock();
    Analytics.track('bp_rest_start', {'sec': seconds});
    state = MeasureState(
      step: MeasureStep.resting,
      imagePath: null,
      samples: state.samples,
      contexts: state.contexts,
      rested: false,
      restTotal: seconds,
      restEndsAt: clock().add(Duration(seconds: seconds)),
      sessionId: state.sessionId ?? _newSessionId(),
      symptoms: state.symptoms,
    );
    final key = seconds >= bpCaffeineWaitSeconds
        ? BpScript.caffeineSmoke
        : seconds <= bpBetweenReadingsSeconds
        ? BpScript.secondReading
        : BpScript.prep;
    unawaited(_say(bpScriptText(key)));
  }

  /// Vy báo thời gian còn lại lúc đang nghỉ (chỉ khi người dùng bật đọc lời khuyên).
  void sayRestLeft(int seconds) =>
      unawaited(_say(hon('Còn ${seconds ~/ 60} phút nữa. Bác cứ ngồi yên, tựa lưng nhé.')));

  /// Hết giờ nghỉ: số đo tới là đủ chuẩn nếu đã ngồi ≥ 5 phút, hoặc đây là số thứ hai sát số đủ chuẩn.
  void finishRest() {
    final waited = state.restTotal;
    final rested =
        waited >= bpRestSeconds ||
        (state.samples.isNotEmpty && state.samples.last.rested);
    Analytics.track('bp_rest_done', {'sec': waited});
    // Vy báo ngay khi hết giờ để người dùng không phải nhìn màn hình đoán.
    unawaited(_say(hon('Hết giờ nghỉ rồi. Bác đưa màn hình máy đo vào khung rồi bấm nút chụp nhé.')));
    state = MeasureState(
      step: MeasureStep.ready,
      samples: state.samples,
      contexts: state.contexts,
      rested: rested,
      restTotal: waited,
      sessionId: state.sessionId,
      symptoms: state.symptoms,
    );
  }

  /// "Bỏ qua, đo luôn": vẫn đo được nhưng số này bị đánh dấu chưa đủ chuẩn.
  void skipRest() {
    Analytics.track('bp_rest_skip');
    final elapsed = _restStartedAt == null
        ? 0
        : clock().difference(_restStartedAt!).inSeconds;
    state = MeasureState(
      step: MeasureStep.ready,
      samples: state.samples,
      contexts: state.contexts,
      rested: false,
      restTotal: elapsed,
      sessionId: state.sessionId,
      symptoms: state.symptoms,
    );
  }

  /// Đọc số chưa được: quay lại camera, giữ nguyên phiên đo (không bắt chuẩn bị và ngồi nghỉ lại).
  void retakePhoto() => state = MeasureState(
    step: MeasureStep.ready,
    samples: state.samples,
    contexts: state.contexts,
    rested: state.rested,
    restTotal: state.restTotal,
    sessionId: state.sessionId,
    symptoms: state.symptoms,
  );

  /// Người dùng trả lời hỏi triệu chứng khi huyết áp rất cao.
  Future<void> answerSymptoms(Set<String> which) async {
    final has = which.isNotEmpty;
    Analytics.track('bp_symptom_flag', {'has': has});
    final sid = state.sessionId;
    if (sid != null) {
      unawaited(
        ref
            .read(bpRepositoryProvider)
            .markSymptoms(sid, has ? which.toList() : ['none'])
            .catchError((_) {}),
      );
    }
    final d = bpDecide(state.samples, context: state.contexts, symptoms: has);
    final r = state.reading;
    final advice = r == null ? null : bpAdvice(r, decision: d);
    state = state.copyWith(symptoms: has, decision: d, advice: advice);
    if (advice != null) unawaited(_say(advice));
  }

  /// Người dùng cho biết máy có báo nhịp tim không đều không (có thể là rung nhĩ).
  Future<void> answerIrregular(bool yes) async {
    Analytics.track('bp_irregular', {'yes': yes});
    state = state.copyWith(irregular: yes);
    if (!yes) return;
    final sid = state.sessionId;
    final ctx = [...?state.reading?.context, 'irregular_pulse'];
    if (sid != null) {
      unawaited(
        ref
            .read(bpRepositoryProvider)
            .markContext(sid, ctx)
            .catchError((_) {}),
      );
    }
    unawaited(_say(bpScriptText(BpScript.irregular)));
  }

  _Pending? _pending;

  /// Số đọc có vẻ lạ: người dùng xác nhận đúng thì mới lưu và đưa lời khuyên.
  Future<void> confirmReading() async {
    final p = _pending;
    if (p == null) return;
    _pending = null;
    Analytics.track('bp_confirm', {'ok': true});
    await _finish(p.imagePath, p.scan, p.parsed, p.history, p.prior);
  }

  /// Số đọc sai: bỏ, chụp lại (không lưu gì).
  void rejectReading() {
    Analytics.track('bp_confirm', {'ok': false});
    _pending = null;
    retakePhoto();
  }

  Future<void> _say(String text) async {
    try {
      if (!await ref.read(speakAdviceProvider.future)) return;
      await ref.read(adviceSpeakerProvider).replace(text);
    } catch (_) {}
  }

  /// Khi có kết quả nguy cơ và từ "cần chú ý" trở lên thì đọc nối tiếp, nếu vẫn đang ở kết quả của lần đo này.
  Future<void> _speakRisk(BpReading reading) async {
    try {
      if (!identical(state.reading, reading)) return;
      final risk = ref.read(riskRunnerProvider).value;
      if (risk == null || !risk.level.worthMentioning) return;
      if (!await ref.read(speakAdviceProvider.future)) return;
      if (!identical(state.reading, reading)) return;
      await ref.read(adviceSpeakerProvider).say(riskSpokenDetailed(risk));
    } catch (_) {}
  }

  MeasureState _failed(String imagePath, String error) => MeasureState(
    step: MeasureStep.failed,
    imagePath: imagePath,
    error: error,
    samples: state.samples,
    contexts: state.contexts,
    rested: state.rested,
    sessionId: state.sessionId,
    symptoms: state.symptoms,
  );

  Future<void> process(String imagePath) async {
    unawaited(ref.read(adviceSpeakerProvider).stop());
    final prior = state;
    state = MeasureState(
      step: MeasureStep.analyzing,
      imagePath: imagePath,
      samples: prior.samples,
      contexts: prior.contexts,
      rested: prior.rested,
      restTotal: prior.restTotal,
      sessionId: prior.sessionId ?? _newSessionId(),
      symptoms: prior.symptoms,
    );
    ref.read(riskRunnerProvider.notifier).clear();
    try {
      // Tải lịch sử song song với lúc đọc ảnh để không phải chờ thêm.
      final historyF = ref
          .read(bpReadingsProvider.future)
          .then<List<BpReading>>((l) => l, onError: (_) => <BpReading>[]);
      final scan = await ref.read(bpOcrEngineProvider).scan(imagePath);
      final parsed = BpExtractor.fromValues(scan.values, source: 'ocr_ai');
      if (parsed == null || !parsed.isValid) {
        Analytics.track('measure', {'ok': false});
        state = _failed(imagePath, 'Chưa đọc được số');
        return;
      }
      final history = await historyF;

      // Số lạ (huyết áp quá cao, chênh lệch quá nhỏ/lớn, nhảy so với số trước): hỏi lại trước khi lưu.
      if (bpLooksSuspicious(
        parsed.systolic,
        parsed.diastolic,
        previous: prior.samples.isEmpty ? null : prior.samples.last,
      )) {
        _pending = _Pending(imagePath, scan, parsed, history, prior);
        Analytics.track('bp_confirm_ask');
        state = MeasureState(
          step: MeasureStep.confirm,
          imagePath: imagePath,
          reading: BpReading(
            systolic: parsed.systolic,
            diastolic: parsed.diastolic,
            pulse: parsed.pulse,
            measuredAt: parsed.measuredAt,
            source: parsed.source,
          ),
          samples: prior.samples,
          contexts: prior.contexts,
          rested: prior.rested,
          restTotal: prior.restTotal,
          sessionId: prior.sessionId,
          symptoms: prior.symptoms,
        );
        return;
      }
      await _finish(imagePath, scan, parsed, history, prior);
    } catch (e) {
      state = _failed(imagePath, errorMessage(e));
    }
  }

  Future<void> _finish(
    String imagePath,
    dynamic scan,
    dynamic parsed,
    List<BpReading> history,
    MeasureState prior,
  ) async {
    try {
      // Gộp vào phiên (tối đa 3 số). Số đo này đủ chuẩn nếu trước đó đã ngồi nghỉ đủ.
      final samples = [
        ...prior.samples,
        BpSample(parsed.systolic, parsed.diastolic, rested: prior.rested),
      ];
      final capped = samples.length > 3
          ? samples.sublist(samples.length - 3)
          : samples;
      final decision = bpDecide(
        capped,
        context: prior.contexts,
        symptoms: prior.symptoms,
      );
      final sid = state.sessionId;
      final reading = BpReading(
        systolic: parsed.systolic,
        diastolic: parsed.diastolic,
        pulse: parsed.pulse,
        measuredAt: parsed.measuredAt,
        source: parsed.source,
        sessionId: sid,
        readingNo: capped.length,
        context: [
          for (final c in prior.contexts)
            switch (c) {
              BpContext.wokeUp => 'woke_up',
              BpContext.exertion => 'exertion',
              BpContext.caffeineSmoke => 'caffeine_smoke',
            },
          if (prior.rested) 'rested',
        ],
        restedSeconds: prior.restTotal > 0 ? prior.restTotal : null,
        protocolOk: prior.rested,
      );
      final advice = bpAdvice(
        reading,
        decision: decision,
        previous: history.isEmpty ? null : history.first,
      );

      // Hiện kết quả ngay, việc lưu chạy ngầm.
      state = MeasureState(
        step: MeasureStep.done,
        imagePath: imagePath,
        reading: reading,
        advice: advice,
        saving: true,
        samples: capped,
        contexts: prior.contexts,
        decision: decision,
        rested: prior.rested,
        restTotal: prior.restTotal,
        sessionId: sid,
        symptoms: prior.symptoms,
      );
      unawaited(_say(advice));

      final draft = OcrDraft(
        imagePath: imagePath,
        rawText: scan.rawText,
        values: scan.values,
      );
      final ok = await ref
          .read(ocrControllerProvider.notifier)
          .save(draft, 'Huyết áp', scan.values, reading: reading);
      if (!ok) {
        final e = ref.read(ocrControllerProvider).error;
        state = _failed(
          imagePath,
          e == null ? 'Chưa lưu được' : errorMessage(e),
        );
        return;
      }
      Analytics.track('measure', {
        'ok': true,
        'category': reading.category.code,
        'n': capped.length,
        'protocol_ok': reading.protocolOk,
      });
      if (capped.length >= 2) Analytics.track('bp_second_reading');
      // Tự đánh giá nguy cơ ngay sau khi lưu; kết quả hiện ở màn đo khi có.
      final riskRun = ref.read(riskRunnerProvider.notifier).run();
      state = MeasureState(
        step: MeasureStep.done,
        imagePath: imagePath,
        reading: reading,
        advice: advice,
        samples: capped,
        contexts: prior.contexts,
        decision: decision,
        rested: prior.rested,
        restTotal: prior.restTotal,
        sessionId: sid,
        symptoms: prior.symptoms,
      );
      unawaited(riskRun.then((_) => _speakRisk(reading)));
    } catch (e) {
      state = _failed(imagePath, errorMessage(e));
    }
  }
}

class _Pending {
  const _Pending(this.imagePath, this.scan, this.parsed, this.history, this.prior);
  final String imagePath;
  final dynamic scan;
  final dynamic parsed;
  final List<BpReading> history;
  final MeasureState prior;
}

final measureControllerProvider =
    NotifierProvider<MeasureController, MeasureState>(MeasureController.new);
