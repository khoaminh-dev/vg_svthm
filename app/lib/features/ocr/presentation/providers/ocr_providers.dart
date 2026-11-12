import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/supabase/supabase_providers.dart';
import '../../data/api_ocr_engine.dart';
import '../../data/mlkit_ocr_engine.dart';
import '../../data/supabase_ocr_repository.dart';
import '../../domain/ocr_models.dart';
import '../../domain/ocr_repositories.dart';

/// Đọc chữ ngay trên máy bằng ML Kit.
final ocrEngineProvider = Provider<OcrEngine>((ref) => MlKitOcrEngine());

/// Đọc bằng AI qua API (dùng token đăng nhập hiện tại).
final aiOcrEngineProvider = Provider<OcrEngine>(
  (ref) => ApiOcrEngine(
    accessToken: () => ref.read(supabaseClientProvider).auth.currentSession?.accessToken,
  ),
);

/// Người dùng đang bật chế độ "Đọc bằng AI" hay không.
class OcrUseAiNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final ocrUseAiProvider = NotifierProvider<OcrUseAiNotifier, bool>(OcrUseAiNotifier.new);

final ocrRepositoryProvider = Provider<OcrRepository>(
  (ref) => SupabaseOcrRepository(ref.watch(supabaseClientProvider)),
);

final imagePickerProvider = Provider<ImagePicker>((ref) => ImagePicker());

/// Lịch sử OCR của người dùng.
final ocrRecordsProvider = FutureProvider.autoDispose<List<OcrRecord>>(
  (ref) => ref.watch(ocrRepositoryProvider).list(),
);

/// Link xem ảnh đã lưu.
final ocrImageUrlProvider = FutureProvider.autoDispose.family<String?, OcrRecord>(
  (ref, record) => ref.watch(ocrRepositoryProvider).imageUrl(record),
);
