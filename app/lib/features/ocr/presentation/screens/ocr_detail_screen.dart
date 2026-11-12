import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../domain/ocr_models.dart';
import '../providers/ocr_controller.dart';
import '../providers/ocr_providers.dart';
import '../../../../core/analytics/analytics.dart';

/// Chi tiết một kết quả OCR đã lưu.
class OcrDetailScreen extends ConsumerWidget {
  const OcrDetailScreen({super.key, required this.record});

  final OcrRecord record;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xoá kết quả này?'),
        content: const Text('Ảnh và số liệu sẽ bị xoá, không khôi phục được.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Xoá')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final ok = await ref.read(ocrControllerProvider.notifier).delete(record);
    if (!context.mounted) return;
    if (ok) {
      context.pop();
    } else {
      final error = ref.read(ocrControllerProvider).error;
      showAppSnackBar(context, errorMessage(error!), error: true);
    }
  }

  String get _asText => record.values
      .map((v) => '${v.label}: ${v.value}${v.unit.isEmpty ? '' : ' ${v.unit}'}')
      .join('\n');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref.watch(ocrImageUrlProvider(record));

    return Scaffold(
      appBar: AppBar(
        title: Text(record.displayTitle),
        actions: [
          IconButton(
            tooltip: 'Sao chép',
            icon: const Icon(Icons.copy),
            onPressed: () async {
              Analytics.track('ocr_copy');
              await Clipboard.setData(ClipboardData(text: _asText));
              if (context.mounted) showAppSnackBar(context, 'Đã sao chép số liệu');
            },
          ),
          IconButton(
            tooltip: 'Xoá',
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              Analytics.track('tap_ocr_delete');
              _delete(context, ref);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            image.when(
              loading: () =>
                  const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
              error: (_, _) => const SizedBox.shrink(),
              data: (url) => url == null
                  ? const SizedBox.shrink()
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.radius),
                      child: Image.network(url, height: 200, fit: BoxFit.cover),
                    ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Số liệu', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (record.values.isEmpty) const Text('Không có số liệu.'),
            for (final v in record.values)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(v.label.isEmpty ? '(không có nhãn)' : v.label),
                trailing: Text(
                  '${v.value}${v.unit.isEmpty ? '' : ' ${v.unit}'}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ExpansionTile(
              title: const Text('Văn bản gốc'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: SelectableText(record.rawText),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
