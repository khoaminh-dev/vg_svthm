import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/analytics/analytics.dart';
import '../../../../core/errors/app_failure.dart';
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
  });

  final MeasureStep step;
  final String? imagePath;
  final BpReading? reading;
  final String? advice;
  final String? error;
}

/// Chụp một lần: đọc số, tự phân loại, tự lưu, rồi nhận xét.
class MeasureController extends Notifier<MeasureState> {
  @override
  MeasureState build() => const MeasureState();

  void reset() => state = const MeasureState();

  Future<void> process(String imagePath) async {
    state = MeasureState(step: MeasureStep.analyzing, imagePath: imagePath);
    try {
      final scan = await ref.read(aiOcrEngineProvider).scan(imagePath);
      final reading = BpExtractor.fromValues(scan.values, source: 'ocr_ai');
      if (reading == null || !reading.isValid) {
        Analytics.track('measure', {'ok': false});
        state = MeasureState(
          step: MeasureStep.failed,
          imagePath: imagePath,
          error: 'Chưa đọc được số',
        );
        return;
      }
      List<BpReading> history = const [];
      try {
        history = await ref.read(bpReadingsProvider.future);
      } catch (_) {}
      final previous = history.isEmpty ? null : history.first;

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
        state = MeasureState(
          step: MeasureStep.failed,
          imagePath: imagePath,
          error: e == null
              ? 'Chưa lưu được'
              : errorMessage(e),
        );
        return;
      }
      Analytics.track('measure', {
        'ok': true,
        'category': reading.category.code,
      });
      state = MeasureState(
        step: MeasureStep.done,
        imagePath: imagePath,
        reading: reading,
        advice: bpAdvice(reading, previous: previous),
      );
    } catch (e) {
      state = MeasureState(
        step: MeasureStep.failed,
        imagePath: imagePath,
        error: errorMessage(e),
      );
    }
  }
}

final measureControllerProvider =
    NotifierProvider<MeasureController, MeasureState>(MeasureController.new);
