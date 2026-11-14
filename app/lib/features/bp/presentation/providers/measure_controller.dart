import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/analytics/analytics.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../health/presentation/providers/health_providers.dart';
import '../../../ocr/domain/ocr_models.dart';
import '../../../ocr/presentation/providers/ocr_controller.dart';
import '../../../ocr/presentation/providers/ocr_providers.dart';
import '../../domain/bp_advice.dart';
import '../../domain/bp_models.dart';
import 'bp_providers.dart';

enum MeasureStep { ready, analyzing, done, failed }

class MeasureState {
  const MeasureState({
    this.step = MeasureStep.ready,
    this.imagePath,
    this.reading,
    this.advice,
    this.error,
    this.saving = false,
  });

  final MeasureStep step;
  final String? imagePath;
  final BpReading? reading;
  final String? advice;
  final String? error;

  /// Đã có kết quả nhưng đang lưu ngầm.
  final bool saving;
}

/// Chụp một lần: đọc số, hiện kết quả và nhận xét ngay, việc lưu chạy ngầm.
class MeasureController extends Notifier<MeasureState> {
  @override
  MeasureState build() => const MeasureState();

  void reset() => state = const MeasureState();

  MeasureState _failed(String imagePath, String error) =>
      MeasureState(step: MeasureStep.failed, imagePath: imagePath, error: error);

  Future<void> process(String imagePath) async {
    state = MeasureState(step: MeasureStep.analyzing, imagePath: imagePath);
    ref.read(riskRunnerProvider.notifier).clear();
    try {
      // Tải lịch sử song song với lúc đọc ảnh để không phải chờ thêm.
      final historyF = ref
          .read(bpReadingsProvider.future)
          .then<List<BpReading>>((l) => l, onError: (_) => <BpReading>[]);
      final scan = await ref.read(bpOcrEngineProvider).scan(imagePath);
      final reading = BpExtractor.fromValues(scan.values, source: 'ocr_ai');
      if (reading == null || !reading.isValid) {
        Analytics.track('measure', {'ok': false});
        state = _failed(imagePath, 'Chưa đọc được số');
        return;
      }
      final history = await historyF;
      final advice = bpAdvice(reading, previous: history.isEmpty ? null : history.first);

      // Hiện kết quả ngay, việc lưu chạy ngầm.
      state = MeasureState(
        step: MeasureStep.done,
        imagePath: imagePath,
        reading: reading,
        advice: advice,
        saving: true,
      );

      final draft = OcrDraft(imagePath: imagePath, rawText: scan.rawText, values: scan.values);
      final ok = await ref
          .read(ocrControllerProvider.notifier)
          .save(draft, 'Huyết áp', scan.values, reading: reading);
      if (!ok) {
        final e = ref.read(ocrControllerProvider).error;
        state = _failed(imagePath, e == null ? 'Chưa lưu được' : errorMessage(e));
        return;
      }
      Analytics.track('measure', {'ok': true, 'category': reading.category.code});
      // Tự đánh giá nguy cơ ngay sau khi lưu; kết quả hiện ở màn đo khi có.
      ref.read(riskRunnerProvider.notifier).run();
      state = MeasureState(
        step: MeasureStep.done,
        imagePath: imagePath,
        reading: reading,
        advice: advice,
      );
    } catch (e) {
      state = _failed(imagePath, errorMessage(e));
    }
  }
}

final measureControllerProvider = NotifierProvider<MeasureController, MeasureState>(
  MeasureController.new,
);
