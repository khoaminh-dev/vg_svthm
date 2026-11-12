import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/errors/app_failure.dart';
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
    XFile? file;
    try {
      file = await ref
          .read(imagePickerProvider)
          .pickImage(source: source, maxWidth: 1800, imageQuality: 85);
    } catch (e, st) {
      // Lỗi quyền camera / plugin: đưa vào state để UI báo, không để thoát ra thành exception.
      state = AsyncError(
        const AppFailure('Không mở được camera hoặc thư viện ảnh, hãy kiểm tra quyền truy cập'),
        st,
      );
      return null;
    }
    if (file == null) {
      // Người dùng huỷ: xoá lỗi cũ để không hiện lại thông báo cũ.
      state = const AsyncData(null);
      return null;
    }

    final path = file.path;
    state = const AsyncLoading();
    OcrDraft? draft;
    state = await AsyncValue.guard(() async {
      final useAi = ref.read(ocrUseAiProvider);
      final engine = ref.read(useAi ? aiOcrEngineProvider : ocrEngineProvider);
      final scan = await engine.scan(path);
      draft = OcrDraft(imagePath: path, rawText: scan.rawText, values: scan.values);
    });
    return draft;
  }

  /// Lưu kết quả OCR; nếu có [reading] thì lưu luôn lần đo huyết áp liên kết với bản ghi đó.
  /// Hai bước được coi như một: nếu lưu huyết áp lỗi thì bản ghi OCR vừa tạo bị hoàn tác.
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
        try {
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
        } catch (_) {
          try {
            await ref.read(ocrRepositoryProvider).delete(record);
          } catch (_) {}
          rethrow;
        }
      }
    });
    // Làm mới danh sách dù thành công hay lỗi để không hiển thị dữ liệu cũ.
    ref.invalidate(ocrRecordsProvider);
    ref.invalidate(bpReadingsProvider);
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
