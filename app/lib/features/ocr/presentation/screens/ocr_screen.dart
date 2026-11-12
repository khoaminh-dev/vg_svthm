import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../providers/ocr_controller.dart';
import '../providers/ocr_providers.dart';
import '../widgets/ocr_record_tile.dart';
import '../../../../core/analytics/analytics.dart';

/// Chụp hoặc chọn ảnh để đọc số liệu, kèm lịch sử các lần đã lưu.
class OcrScreen extends ConsumerWidget {
  const OcrScreen({super.key});

  Future<void> _scan(BuildContext context, WidgetRef ref, ImageSource source) async {
    Analytics.track('ocr_scan', {'source': source.name, 'ai': ref.read(ocrUseAiProvider)});
    final draft = await ref.read(ocrControllerProvider.notifier).scan(source);
    if (!context.mounted) return;
    if (draft == null) {
      final error = ref.read(ocrControllerProvider).error;
      if (error != null) showAppSnackBar(context, errorMessage(error), error: true);
      return;
    }
    context.push(Routes.ocrEdit, extra: draft);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanning = ref.watch(ocrControllerProvider).isLoading;
    final useAi = ref.watch(ocrUseAiProvider);
    final records = ref.watch(ocrRecordsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('OCR số liệu')),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async => ref.refresh(ocrRecordsProvider.future),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Đọc bằng AI'),
                  subtitle: Text(
                    useAi
                        ? 'Chính xác hơn với màn hình LCD, hoá đơn, bảng biểu (cần mạng)'
                        : 'Đọc ngay trên máy, miễn phí, phù hợp chữ in rõ',
                  ),
                  value: useAi,
                  onChanged: scanning
                      ? null
                      : (v) {
                          Analytics.track('toggle_ai_ocr', {'on': v});
                          ref.read(ocrUseAiProvider.notifier).set(v);
                        },
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: scanning ? null : () => _scan(context, ref, ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Chụp ảnh'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        onPressed: scanning ? null : () => _scan(context, ref, ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Chọn ảnh'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Lịch sử', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                records.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(child: Text(errorMessage(e))),
                  ),
                  data: (list) => list.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                            child: Text(
                              'Chưa có kết quả nào.\nChụp một tấm ảnh có số liệu để bắt đầu.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            for (final r in list)
                              OcrRecordTile(
                                record: r,
                                onTap: () {
                                  Analytics.track('open_ocr_record');
                                  context.push(Routes.ocrDetail, extra: r);
                                },
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          if (scanning)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Đang đọc ảnh...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
