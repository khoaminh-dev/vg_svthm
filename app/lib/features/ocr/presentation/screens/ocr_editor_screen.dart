import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../bp/domain/bp_models.dart';
import '../../domain/ocr_models.dart';
import '../providers/ocr_providers.dart';
import '../providers/ocr_controller.dart';
import '../widgets/ocr_value_row.dart';
import '../../../../core/analytics/analytics.dart';

/// Xem lại và sửa tay kết quả OCR trước khi lưu.
class OcrEditorScreen extends ConsumerStatefulWidget {
  const OcrEditorScreen({super.key, required this.draft});

  final OcrDraft draft;

  @override
  ConsumerState<OcrEditorScreen> createState() => _OcrEditorScreenState();
}

class _OcrEditorScreenState extends ConsumerState<OcrEditorScreen> {
  final _title = TextEditingController();
  late final List<EditableOcrRow> _rows;
  bool _saveBp = true;

  @override
  void initState() {
    super.initState();
    _rows = widget.draft.values.map(EditableOcrRow.new).toList();
  }

  @override
  void dispose() {
    _title.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  /// Lần đo huyết áp suy ra từ các dòng đang hiển thị (null nếu không phải kết quả huyết áp).
  BpReading? _currentReading() => BpExtractor.fromValues(
    _rows.where((r) => !r.isEmpty).map((r) => r.toValue()).toList(),
    source: ref.read(ocrUseAiProvider) ? 'ocr_ai' : 'ocr_local',
  );

  Future<void> _save() async {
    final values = _rows.where((r) => !r.isEmpty).map((r) => r.toValue()).toList();
    final reading = _saveBp ? _currentReading() : null;
    final ok = await ref
        .read(ocrControllerProvider.notifier)
        .save(widget.draft, _title.text, values, reading: reading);
    if (!mounted) return;
    if (ok) {
      Analytics.track('ocr_save', {'bp': reading != null, 'rows': values.length});
      showAppSnackBar(context, 'Đã lưu kết quả');
      context.pop();
    } else {
      final error = ref.read(ocrControllerProvider).error;
      showAppSnackBar(context, errorMessage(error!), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(ocrControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Kết quả OCR')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (!kIsWeb)
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.radius),
                child: Image.file(File(widget.draft.imagePath), height: 160, fit: BoxFit.cover),
              ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Tiêu đề (không bắt buộc)'),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(child: Text('Số liệu', style: Theme.of(context).textTheme.titleMedium)),
                TextButton.icon(
                  onPressed: () {
                    Analytics.track('ocr_add_row');
                    setState(() => _rows.add(EditableOcrRow()));
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm dòng'),
                ),
              ],
            ),
            if (_rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Không tìm thấy số liệu nào. Bạn có thể thêm dòng bằng tay.'),
              ),
            for (final row in _rows)
              OcrValueRow(
                key: ObjectKey(row),
                row: row,
                onDelete: () => setState(() {
                  _rows.remove(row);
                  row.dispose();
                }),
              ),
            ListenableBuilder(
              listenable: Listenable.merge([for (final r in _rows) ...[r.label, r.value]]),
              builder: (context, _) {
                final r = _currentReading();
                if (r == null) return const SizedBox.shrink();
                return Card(
                  child: SwitchListTile(
                    value: _saveBp,
                    onChanged: (v) => setState(() => _saveBp = v),
                    title: const Text('Lưu vào theo dõi huyết áp'),
                    subtitle: Text(
                      '${r.systolic}/${r.diastolic}'
                      '${r.pulse != null ? ' · mạch ${r.pulse}' : ''} mmHg · ${r.category.label}',
                      style: TextStyle(color: r.category.color, fontWeight: FontWeight.w600),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            ExpansionTile(
              title: const Text('Văn bản gốc'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: SelectableText(
                    widget.draft.rawText.isEmpty
                        ? '(không đọc được chữ nào)'
                        : widget.draft.rawText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(label: 'Lưu', loading: saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
