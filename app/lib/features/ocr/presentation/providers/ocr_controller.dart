import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../bp/domain/bp_models.dart';
import '../../../bp/presentation/providers/bp_providers.dart';
import '../../domain/ocr_models.dart';
import 'ocr_providers.dart';

/// Các hành động OCR; state là trạng thái loading/lỗi của hành động gần nhất.
class OcrController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Chụp hoặc chọn ảnh rồi đọc chữ. Trả về `null` nếu người dùng huỷ hoặc lỗi (lỗi nằm trong state).
  Future<OcrDraft?> scan(ImageSource source) async {
    final file = await ref
        .read(imagePickerProvider)
        .pickImage(source: source, maxWidth: 1800, imageQuality: 85);
    if (file == null) return null;

    state = const AsyncLoading();
    OcrDraft? draft;
    state = await AsyncValue.guard(() async {
      final useAi = ref.read(ocrUseAiProvider);
      final engine = ref.read(useAi ? aiOcrEngineProvider : ocrEngineProvider);
      final scan = await engine.scan(file.path);
      draft = OcrDraft(imagePath: file.path, rawText: scan.rawText, values: scan.values);
    });
    return draft;
  }

  /// Lưu kết quả OCR; nếu có [reading] thì lưu luôn lần đo huyết áp liên kết với bản ghi đó.
  /// Lưu kết quả OCR; nếu có [reading] thì lưu luôn lần đo huyết áp liên kết với bản ghi đó.
  Future<bool> save(
    OcrDraft draft,
    String title,
    List<OcrValue> values, {
    BpReading? reading,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final record = await ref
          .read(ocrRepositoryProvider)
          .save(
            title: title,
            rawText: draft.rawText,
            values: values,
            localImagePath: draft.imagePath,
          );
      if (reading != null) {
        await ref
            .read(bpRepositoryProvider)
            .add(
              BpReading(
                systolic: reading.systolic,
                diastolic: reading.diastolic,
                pulse: reading.pulse,
                measuredAt: reading.measuredAt,
                source: reading.source,
                ocrRecordId: record.id,
              ),
            );
      }
    });
    if (!state.hasError) {
      ref.invalidate(ocrRecordsProvider);
      ref.invalidate(bpReadingsProvider);
    }
    return !state.hasError;
  }

  Future<bool> delete(OcrRecord record) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(ocrRepositoryProvider).delete(record));
    if (!state.hasError) ref.invalidate(ocrRecordsProvider);
    return !state.hasError;
  }
}

final ocrControllerProvider = AsyncNotifierProvider<OcrController, void>(OcrController.new);
